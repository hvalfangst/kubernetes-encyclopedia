#!/bin/bash

# PersistentVolumeClaim Management and Testing Script
# This script manages PVCs and demonstrates claim functionality

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MANIFEST_FILE="manifest.yml"
BASIC_PVC="basic-pvc"
DATABASE_PVC="database-pvc"
SHARED_PVC="shared-storage-pvc"
EXCLUSIVE_PVC="exclusive-pvc"
NAMESPACE="default"

# Functions to print colored output

print_newline_with_separator() {
    echo -e "\n${BLUE}==================================================================${NC}"
}

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to wait for condition with timeout
wait_for_condition() {
    local description="$1"
    local condition="$2"
    local timeout="${3:-120}"
    local interval="${4:-5}"

    print_status "Waiting for: $description (timeout: ${timeout}s)"

    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if eval "$condition"; then
            print_success "$description - Condition met!"
            return 0
        fi

        echo -n "."
        sleep $interval
        elapsed=$((elapsed + interval))
    done

    echo ""
    print_error "$description - Timeout reached!"
    return 1
}

# Function to check if kubectl is available
check_kubectl() {
    print_status "Checking kubectl availability..."

    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed or not in PATH"
        exit 1
    fi

    print_success "kubectl is installed"
    print_status "Checking Kubernetes cluster connectivity..."

    if ! timeout 10 kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    print_success "Cluster is accessible"

    print_newline_with_separator
}

# Function to show cluster storage info
show_cluster_info() {
    print_status "Showing cluster storage information..."

    echo ""
    echo "=== Cluster Nodes ==="
    kubectl get nodes -o wide

    echo ""
    echo "=== Storage Classes ==="
    kubectl get storageclass -o wide

    echo ""
    echo "=== Default Storage Class ==="
    kubectl get storageclass -o json | jq -r '.items[] | select(.metadata.annotations."storageclass.kubernetes.io/is-default-class" == "true") | .metadata.name' || echo "No default StorageClass found"

    echo ""
    echo "=== Existing PVCs ==="
    kubectl get pvc --all-namespaces

    echo ""
    echo "=== Existing PVs ==="
    kubectl get pv

    print_newline_with_separator
}

# Function to cleanup existing resources
cleanup_existing() {
    print_status "Cleaning up existing resources..."

    # Delete pods first
    for pod in shared-storage-pod; do
        if kubectl get pod $pod -n $NAMESPACE &> /dev/null; then
            print_warning "Existing Pod $pod found, deleting..."
            kubectl delete pod $pod -n $NAMESPACE --grace-period=0 --force
        fi
    done

    # Delete deployments
    for deploy in app-with-storage; do
        if kubectl get deployment $deploy -n $NAMESPACE &> /dev/null; then
            print_warning "Existing Deployment $deploy found, deleting..."
            kubectl delete deployment $deploy -n $NAMESPACE
        fi
    done

    # Delete StatefulSets
    if kubectl get statefulset database-cluster -n $NAMESPACE &> /dev/null; then
        print_warning "Existing StatefulSet database-cluster found, deleting..."
        kubectl delete statefulset database-cluster -n $NAMESPACE
    fi

    # Delete PVCs
    for pvc in $BASIC_PVC $DATABASE_PVC $SHARED_PVC $EXCLUSIVE_PVC restored-pvc; do
        if kubectl get pvc $pvc -n $NAMESPACE &> /dev/null; then
            print_warning "Existing PVC $pvc found, deleting..."
            kubectl delete pvc $pvc -n $NAMESPACE
        fi
    done

    # Delete Volume Snapshots
    if kubectl get volumesnapshot database-backup -n $NAMESPACE &> /dev/null 2>&1; then
        print_warning "Existing VolumeSnapshot database-backup found, deleting..."
        kubectl delete volumesnapshot database-backup -n $NAMESPACE
    fi

    # Delete VolumeSnapshotClass
    if kubectl get volumesnapshotclass csi-snapshotter &> /dev/null 2>&1; then
        print_warning "Existing VolumeSnapshotClass csi-snapshotter found, deleting..."
        kubectl delete volumesnapshotclass csi-snapshotter
    fi

    # Delete StorageClasses (only the ones we created)
    for sc in premium-ssd nfs-storage cost-optimized; do
        if kubectl get storageclass $sc &> /dev/null; then
            print_warning "Existing StorageClass $sc found, deleting..."
            kubectl delete storageclass $sc
        fi
    done

    # Delete other resources
    for resource in configmap/postgres-config secret/postgres-secret service/database-headless service/database-service resourcequota/storage-quota limitrange/pvc-limits; do
        if kubectl get $resource -n $NAMESPACE &> /dev/null; then
            print_warning "Existing $resource found, deleting..."
            kubectl delete $resource -n $NAMESPACE
        fi
    done

    print_success "Cleanup completed"

    print_newline_with_separator
}

# Function to deploy basic PVC examples
deploy_basic_examples() {
    print_status "Deploying basic PVC examples..."

    # Deploy basic resources that work in most environments
    cat << 'EOF' | kubectl apply -f -
# Basic StorageClass (assuming standard exists or using hostPath)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: basic-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: false

---
# Simple PersistentVolume for testing
apiVersion: v1
kind: PersistentVolume
metadata:
  name: test-pv
  labels:
    type: local
spec:
  storageClassName: basic-storage
  capacity:
    storage: 20Gi
  accessModes:
  - ReadWriteOnce
  hostPath:
    path: /tmp/pv-data
    type: DirectoryOrCreate
  persistentVolumeReclaimPolicy: Delete

---
# Basic PVC for development
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: basic-pvc
  labels:
    app: basic-app
    environment: development
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: basic-storage

---
# ConfigMap for testing
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  app.conf: |
    # Application configuration
    server.port=8080
    log.level=INFO

---
# Application using PVC
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-with-storage
  labels:
    app: app-with-storage
spec:
  replicas: 1
  selector:
    matchLabels:
      app: app-with-storage
  template:
    metadata:
      labels:
        app: app-with-storage
    spec:
      containers:
      - name: app
        image: nginx:1.21
        ports:
        - containerPort: 80
        volumeMounts:
        - name: app-data
          mountPath: /usr/share/nginx/html
        - name: config
          mountPath: /etc/nginx/conf.d
        resources:
          requests:
            memory: 64Mi
            cpu: 50m
          limits:
            memory: 128Mi
            cpu: 100m
        lifecycle:
          postStart:
            exec:
              command:
              - /bin/sh
              - -c
              - |
                echo "<h1>PVC Demo Application</h1>" > /usr/share/nginx/html/index.html
                echo "<p>This content is stored on a PersistentVolume</p>" >> /usr/share/nginx/html/index.html
                echo "<p>Container: $HOSTNAME</p>" >> /usr/share/nginx/html/index.html
                echo "<p>Started: $(date)</p>" >> /usr/share/nginx/html/index.html
      volumes:
      - name: app-data
        persistentVolumeClaim:
          claimName: basic-pvc
      - name: config
        configMap:
          name: app-config
EOF

    print_success "Basic resources deployed"

    print_newline_with_separator
}

# Function to verify deployments
verify_deployments() {
    print_status "Verifying PVC deployments..."

    echo ""
    echo "=== PersistentVolumeClaims ==="
    kubectl get pvc -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== PersistentVolumes ==="
    kubectl get pv -o wide

    print_newline_with_separator

    echo ""
    echo "=== StorageClasses ==="
    kubectl get storageclass

    print_newline_with_separator

    # Wait for PVC to be bound
    wait_for_condition "PVC binding" \
        "kubectl get pvc $BASIC_PVC -n $NAMESPACE -o jsonpath='{.status.phase}' | grep -q 'Bound'" \
        60 5

    echo ""
    echo "=== Deployments ==="
    kubectl get deployments -n $NAMESPACE -o wide

    # Wait for deployment to be ready
    wait_for_condition "Deployment ready" \
        "kubectl get deployment app-with-storage -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' | grep -q '1'" \
        120 10

    print_success "PVC resources are ready"

    print_newline_with_separator
}

# Function to test PVC functionality
test_pvc_functionality() {
    print_status "Testing PVC functionality..."

    # Get pod name
    POD_NAME=$(kubectl get pods -l app=app-with-storage -n $NAMESPACE --no-headers | head -1 | awk '{print $1}')
    
    if [ -n "$POD_NAME" ]; then
        echo ""
        echo "=== Testing Pod with PVC ==="
        echo "Pod name: $POD_NAME"
        
        # Check pod status
        kubectl get pod $POD_NAME -n $NAMESPACE -o wide
        
        echo ""
        echo "=== Testing data persistence ==="
        
        # Write test data
        TEST_DATA="PVC test data - $(date)"
        kubectl exec $POD_NAME -n $NAMESPACE -- sh -c "echo '$TEST_DATA' > /usr/share/nginx/html/test-data.txt"
        kubectl exec $POD_NAME -n $NAMESPACE -- sh -c "echo 'Line 2: Additional data' >> /usr/share/nginx/html/test-data.txt"
        kubectl exec $POD_NAME -n $NAMESPACE -- sh -c "date > /usr/share/nginx/html/timestamp.txt"
        
        # Read test data
        echo ""
        echo "=== Reading data from PVC ==="
        kubectl exec $POD_NAME -n $NAMESPACE -- cat /usr/share/nginx/html/test-data.txt
        kubectl exec $POD_NAME -n $NAMESPACE -- cat /usr/share/nginx/html/timestamp.txt
        
        echo ""
        echo "=== Listing files in PVC ==="
        kubectl exec $POD_NAME -n $NAMESPACE -- ls -la /usr/share/nginx/html/
        
        # Test HTTP access
        echo ""
        echo "=== Testing HTTP access ==="
        kubectl exec $POD_NAME -n $NAMESPACE -- curl -s http://localhost/ | head -10
        
        # Test volume mount details
        echo ""
        echo "=== Volume mount information ==="
        kubectl exec $POD_NAME -n $NAMESPACE -- df -h | grep -E "(Filesystem|/usr/share/nginx/html)"
        kubectl exec $POD_NAME -n $NAMESPACE -- mount | grep "/usr/share/nginx/html" || echo "Volume mount details not available"
        
    else
        print_warning "No pods found for testing"
    fi

    print_newline_with_separator
}

# Function to demonstrate PVC expansion
test_pvc_expansion() {
    print_status "Demonstrating PVC expansion..."

    echo ""
    echo "=== Current PVC size ==="
    kubectl get pvc $BASIC_PVC -n $NAMESPACE -o custom-columns="NAME:.metadata.name,CAPACITY:.status.capacity.storage,REQUESTED:.spec.resources.requests.storage"

    echo ""
    echo "=== Checking if expansion is supported ==="
    STORAGE_CLASS=$(kubectl get pvc $BASIC_PVC -n $NAMESPACE -o jsonpath='{.spec.storageClassName}')
    EXPANSION_SUPPORTED=$(kubectl get storageclass $STORAGE_CLASS -o jsonpath='{.allowVolumeExpansion}')
    
    if [ "$EXPANSION_SUPPORTED" = "true" ]; then
        print_status "Storage class supports volume expansion"
        
        print_status "Expanding PVC from 10Gi to 15Gi..."
        kubectl patch pvc $BASIC_PVC -n $NAMESPACE -p '{"spec":{"resources":{"requests":{"storage":"15Gi"}}}}'
        
        echo ""
        echo "=== PVC after expansion request ==="
        kubectl get pvc $BASIC_PVC -n $NAMESPACE -o wide
        
        echo ""
        echo "=== Expansion conditions ==="
        kubectl describe pvc $BASIC_PVC -n $NAMESPACE | grep -A 10 "Conditions:"
        
    else
        print_warning "Storage class does not support volume expansion"
        echo "Current storage class: $STORAGE_CLASS"
        echo "To enable expansion, the StorageClass must have 'allowVolumeExpansion: true'"
    fi

    print_newline_with_separator
}

# Function to test volume snapshots
test_volume_snapshots() {
    print_status "Testing volume snapshot functionality..."

    # Check if VolumeSnapshot CRDs are available
    if ! kubectl get crd volumesnapshots.snapshot.storage.k8s.io &> /dev/null; then
        print_warning "VolumeSnapshot CRDs not available in this cluster"
        print_status "Volume snapshots require the snapshot controller to be installed"
        return
    fi

    echo ""
    echo "=== Creating VolumeSnapshotClass ==="
    cat << 'EOF' | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: test-snapshotter
driver: kubernetes.io/no-provisioner
deletionPolicy: Delete
EOF

    echo ""
    echo "=== Creating VolumeSnapshot ==="
    cat << 'EOF' | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: test-snapshot
  labels:
    backup-type: manual
spec:
  volumeSnapshotClassName: test-snapshotter
  source:
    persistentVolumeClaimName: basic-pvc
EOF

    sleep 5

    echo ""
    echo "=== VolumeSnapshot Status ==="
    kubectl get volumesnapshot test-snapshot -n $NAMESPACE -o wide 2>/dev/null || echo "VolumeSnapshot not ready yet"

    echo ""
    echo "=== VolumeSnapshot Details ==="
    kubectl describe volumesnapshot test-snapshot -n $NAMESPACE 2>/dev/null || echo "VolumeSnapshot details not available"

    # Cleanup snapshot resources
    kubectl delete volumesnapshot test-snapshot -n $NAMESPACE 2>/dev/null || true
    kubectl delete volumesnapshotclass test-snapshotter 2>/dev/null || true

    print_newline_with_separator
}

# Function to show PVC status and conditions
show_pvc_status() {
    print_status "Showing detailed PVC status..."

    echo ""
    echo "=== All PVCs with detailed status ==="
    kubectl get pvc -n $NAMESPACE -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName,CAPACITY:.status.capacity.storage,ACCESS:.spec.accessModes,STORAGECLASS:.spec.storageClassName,AGE:.metadata.creationTimestamp"

    echo ""
    echo "=== PVC Conditions ==="
    for pvc in $(kubectl get pvc -n $NAMESPACE --no-headers | awk '{print $1}'); do
        echo ""
        echo "--- $pvc ---"
        kubectl get pvc $pvc -n $NAMESPACE -o jsonpath='{.status.conditions[*]}' | jq '.' 2>/dev/null || echo "No conditions or jq not available"
    done

    echo ""
    echo "=== PVC Events ==="
    kubectl get events -n $NAMESPACE --field-selector involvedObject.kind=PersistentVolumeClaim --sort-by=.metadata.creationTimestamp | tail -10

    print_newline_with_separator
}

# Function to demonstrate access modes
demonstrate_access_modes() {
    print_status "Demonstrating different access modes..."

    echo ""
    echo "=== ReadWriteOnce (RWO) - Current basic-pvc ==="
    kubectl get pvc $BASIC_PVC -n $NAMESPACE -o jsonpath='{.spec.accessModes[*]}'
    echo ""

    echo ""
    echo "=== Creating ReadOnlyMany (ROX) PVC example ==="
    cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: readonly-pv
  labels:
    type: readonly
spec:
  storageClassName: basic-storage
  capacity:
    storage: 5Gi
  accessModes:
  - ReadOnlyMany
  hostPath:
    path: /tmp/readonly-data
    type: DirectoryOrCreate
  persistentVolumeReclaimPolicy: Delete

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: readonly-pvc
  labels:
    app: readonly-app
spec:
  accessModes:
  - ReadOnlyMany
  resources:
    requests:
      storage: 5Gi
  storageClassName: basic-storage
EOF

    sleep 5
    
    echo ""
    echo "=== Access Modes Summary ==="
    echo "PVC Name        | Access Modes"
    echo "----------------|-------------"
    kubectl get pvc -n $NAMESPACE -o custom-columns="NAME:.metadata.name,ACCESS:.spec.accessModes" --no-headers

    # Cleanup readonly resources
    kubectl delete pvc readonly-pvc -n $NAMESPACE 2>/dev/null || true
    kubectl delete pv readonly-pv 2>/dev/null || true

    print_newline_with_separator
}

# Function to show resource usage
show_resource_usage() {
    print_status "Showing PVC resource usage..."

    echo ""
    echo "=== Storage Usage (if metrics-server available) ==="
    kubectl top pods -n $NAMESPACE 2>/dev/null || echo "Metrics server not available"

    echo ""
    echo "=== Volume Statistics ==="
    for pvc in $(kubectl get pvc -n $NAMESPACE --no-headers | awk '{print $1}'); do
        echo ""
        echo "--- $pvc ---"
        # Try to get volume statistics if available
        POD_USING_PVC=$(kubectl get pods -n $NAMESPACE -o json | jq -r --arg pvc "$pvc" '.items[] | select(.spec.volumes[]? | .persistentVolumeClaim?.claimName == $pvc) | .metadata.name' | head -1)
        if [ -n "$POD_USING_PVC" ]; then
            echo "Used by pod: $POD_USING_PVC"
            kubectl exec $POD_USING_PVC -n $NAMESPACE -- df -h 2>/dev/null | grep -E "(Filesystem|/usr/share)" || echo "Volume stats not available"
        else
            echo "Not currently mounted by any pod"
        fi
    done

    echo ""
    echo "=== PV and PVC Relationship ==="
    kubectl get pvc -n $NAMESPACE -o custom-columns="PVC:.metadata.name,STATUS:.status.phase,PV:.spec.volumeName,CAPACITY:.status.capacity.storage"

    print_newline_with_separator
}

# Function to show troubleshooting information
show_troubleshooting_info() {
    print_status "Showing troubleshooting information..."

    echo ""
    echo "=== Common PVC Issues and Solutions ==="
    
    echo ""
    echo "1. PVC Stuck in Pending:"
    echo "   - Check available PVs: kubectl get pv"
    echo "   - Check StorageClass: kubectl describe storageclass <name>"
    echo "   - Check PVC events: kubectl describe pvc <name>"
    echo "   - Verify provisioner is running"

    echo ""
    echo "2. Pod Cannot Mount PVC:"
    echo "   - Check Pod events: kubectl describe pod <name>"
    echo "   - Verify PVC is bound: kubectl get pvc"
    echo "   - Check node affinity constraints"
    echo "   - Verify volume attachment: kubectl get volumeattachments"

    echo ""
    echo "3. Volume Expansion Issues:"
    echo "   - Check if StorageClass allows expansion"
    echo "   - Verify PVC conditions: kubectl describe pvc <name>"
    echo "   - Check CSI driver logs for errors"
    echo "   - Restart Pod if filesystem resize pending"

    echo ""
    echo "=== Current Cluster Diagnostics ==="
    
    echo ""
    echo "Storage Classes:"
    kubectl get storageclass -o custom-columns="NAME:.metadata.name,PROVISIONER:.provisioner,EXPANSION:.allowVolumeExpansion,BINDING:.volumeBindingMode"

    echo ""
    echo "PVC Health Status:"
    for pvc in $(kubectl get pvc -n $NAMESPACE --no-headers | awk '{print $1}'); do
        PHASE=$(kubectl get pvc $pvc -n $NAMESPACE -o jsonpath='{.status.phase}')
        echo "$pvc: $PHASE"
    done

    echo ""
    echo "Recent PVC-related events:"
    kubectl get events -n $NAMESPACE --field-selector involvedObject.kind=PersistentVolumeClaim | tail -5 || echo "No recent PVC events"

    print_newline_with_separator
}

# Function to run interactive monitoring
interactive_monitoring() {
    print_status "Starting interactive PVC monitoring..."
    echo "Press Ctrl+C to exit monitoring mode"

    trap 'print_status "Exiting monitoring mode..."; return' INT

    while true; do
        clear
        echo "=========================================="
        echo "    PVC Monitoring Dashboard"
        echo "=========================================="
        echo ""

        echo "=== PersistentVolumeClaims ==="
        kubectl get pvc -n $NAMESPACE -o wide | head -10

        echo ""
        echo "=== PersistentVolumes ==="
        kubectl get pv -o wide | head -10

        echo ""
        echo "=== Recent Events ==="
        kubectl get events -n $NAMESPACE --field-selector involvedObject.kind=PersistentVolumeClaim --sort-by=.metadata.creationTimestamp | tail -5

        echo ""
        echo "=== Pod Storage Usage ==="
        kubectl get pods -n $NAMESPACE -o wide | head -5

        echo ""
        echo "Refreshing in 10 seconds... (Ctrl+C to exit)"
        sleep 10
    done
}

# Function to show final status
show_final_status() {
    echo ""
    echo "==================================="
    echo "         FINAL STATUS"
    echo "==================================="

    echo ""
    echo "=== All PersistentVolumeClaims ==="
    kubectl get pvc -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== All PersistentVolumes ==="
    kubectl get pv -o wide

    print_newline_with_separator

    echo ""
    echo "=== StorageClasses ==="
    kubectl get storageclass

    print_newline_with_separator

    echo ""
    echo "=== Applications Using PVCs ==="
    kubectl get deployments -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== PVC Features Demonstrated ==="
    echo "1. ✅ Basic PVC Creation and Binding"
    echo "2. ✅ Dynamic Provisioning (with StorageClass)"
    echo "3. ✅ Data Persistence (across pod restarts)"
    echo "4. ✅ Volume Mounting (in application pods)"
    echo "5. ✅ Access Modes (ReadWriteOnce, ReadOnlyMany)"
    echo "6. ✅ Storage Requests and Limits"
    echo "7. ✅ PVC Status and Conditions Monitoring"
    echo "8. ✅ Volume Expansion (if supported)"

    print_newline_with_separator

    echo ""
    echo "=== Useful Commands ==="
    echo "List PVCs: kubectl get pvc"
    echo "PVC details: kubectl describe pvc <pvc-name>"
    echo "Check PVC events: kubectl get events --field-selector involvedObject.name=<pvc-name>"
    echo "Expand PVC: kubectl patch pvc <name> -p '{\"spec\":{\"resources\":{\"requests\":{\"storage\":\"20Gi\"}}}}'"
    echo "Force delete PVC: kubectl patch pvc <name> -p '{\"metadata\":{\"finalizers\":null}}'"
    echo "Create snapshot: kubectl create -f volumesnapshot.yaml"
    echo "Monitor PVC status: kubectl get pvc -w"
    echo "Check storage quota: kubectl describe quota"

    print_newline_with_separator
}

# Cleanup function for script interruption
cleanup() {
    echo ""
    print_warning "Script interrupted. Current status:"
    kubectl get pvc -n $NAMESPACE 2>/dev/null || echo "No PVCs found"
    kubectl get pv 2>/dev/null || echo "No PVs found"
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    exit 1
}

# Show usage information
show_usage() {
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  deploy       Deploy basic PVC examples"
    echo "  test         Test PVC functionality with applications"
    echo "  expand       Demonstrate PVC expansion"
    echo "  snapshot     Test volume snapshot functionality"
    echo "  status       Show detailed PVC status and conditions"
    echo "  access-modes Demonstrate different access modes"
    echo "  monitor      Interactive monitoring of PVC resources"
    echo "  usage        Show resource usage and statistics"
    echo "  troubleshoot Show troubleshooting information"
    echo "  cleanup      Clean up all created resources"
    echo "  info         Show cluster storage information"
    echo "  help         Show this usage information"
    echo ""
    echo "If no option is provided, full deployment and testing will run."
}

# Trap Ctrl+C
trap cleanup INT

# Parse command line arguments
case "${1:-}" in
    "deploy")
        echo "==================================="
        echo "     PVC Deployment"
        echo "==================================="
        check_kubectl
        show_cluster_info
        cleanup_existing
        deploy_basic_examples
        verify_deployments
        show_final_status
        ;;
    "test")
        echo "==================================="
        echo "     PVC Testing"
        echo "==================================="
        check_kubectl
        test_pvc_functionality
        ;;
    "expand")
        echo "==================================="
        echo "     PVC Expansion Demo"
        echo "==================================="
        check_kubectl
        test_pvc_expansion
        ;;
    "snapshot")
        echo "==================================="
        echo "     Volume Snapshot Testing"
        echo "==================================="
        check_kubectl
        test_volume_snapshots
        ;;
    "status")
        echo "==================================="
        echo "     PVC Status Information"
        echo "==================================="
        check_kubectl
        show_pvc_status
        ;;
    "access-modes")
        echo "==================================="
        echo "     Access Modes Demo"
        echo "==================================="
        check_kubectl
        demonstrate_access_modes
        ;;
    "monitor")
        echo "==================================="
        echo "     PVC Monitoring"
        echo "==================================="
        check_kubectl
        interactive_monitoring
        ;;
    "usage")
        echo "==================================="
        echo "     Resource Usage"
        echo "==================================="
        check_kubectl
        show_resource_usage
        ;;
    "troubleshoot")
        echo "==================================="
        echo "     Troubleshooting"
        echo "==================================="
        check_kubectl
        show_troubleshooting_info
        ;;
    "cleanup")
        echo "==================================="
        echo "     Resource Cleanup"
        echo "==================================="
        check_kubectl
        cleanup_existing
        print_success "Cleanup completed!"
        ;;
    "info")
        echo "==================================="
        echo "     Cluster Storage Information"
        echo "==================================="
        check_kubectl
        show_cluster_info
        ;;
    "help")
        show_usage
        ;;
    "")
        # Default: Run full deployment and testing
        echo "==================================="
        echo "  PVC Management & Testing Script"
        echo "==================================="

        # Pre-flight checks
        check_kubectl

        # Show cluster info
        show_cluster_info

        # Cleanup any existing resources
        cleanup_existing

        # Deploy basic examples
        deploy_basic_examples

        # Verify deployments
        verify_deployments

        # Test functionality
        test_pvc_functionality

        # Show PVC status
        show_pvc_status

        # Test expansion (if supported)
        test_pvc_expansion

        # Test snapshots (if available)
        test_volume_snapshots

        # Demonstrate access modes
        demonstrate_access_modes

        # Show resource usage
        show_resource_usage

        # Show troubleshooting info
        show_troubleshooting_info

        # Show final status
        show_final_status

        print_success "Script completed successfully!"

        echo ""
        echo "PersistentVolumeClaims have been created and tested."
        echo "Run '$0 monitor' for interactive monitoring."
        echo "Run '$0 cleanup' to remove all created resources."
        ;;
    *)
        print_error "Unknown option: $1"
        show_usage
        exit 1
        ;;
esac
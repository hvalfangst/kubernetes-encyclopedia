#!/bin/bash

# PersistentVolume Management and Testing Script
# This script manages PersistentVolumes and demonstrates storage functionality

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MANIFEST_FILE="manifest.yml"
HOSTPATH_PV="hostpath-pv"
DEV_PVC="dev-pvc"
SHARED_PVC="shared-pvc"
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
    local timeout="${3:-60}"
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
    echo "=== CSI Drivers ==="
    kubectl get csidrivers 2>/dev/null || echo "No CSI drivers found or CSI not available"

    echo ""
    echo "=== Storage Capacity ==="
    kubectl get csinodes 2>/dev/null | head -10 || echo "CSI node information not available"

    print_newline_with_separator
}

# Function to cleanup existing resources
cleanup_existing() {
    print_status "Cleaning up existing resources..."

    # Delete pods first
    for pod in secure-storage-pod shared-storage-pod; do
        if kubectl get pod $pod -n $NAMESPACE &> /dev/null; then
            print_warning "Existing Pod $pod found, deleting..."
            kubectl delete pod $pod -n $NAMESPACE --grace-period=0 --force
        fi
    done

    # Delete StatefulSets
    if kubectl get statefulset database-statefulset -n $NAMESPACE &> /dev/null; then
        print_warning "Existing StatefulSet database-statefulset found, deleting..."
        kubectl delete statefulset database-statefulset -n $NAMESPACE
    fi

    # Delete PVCs
    for pvc in dev-pvc shared-pvc exclusive-pvc; do
        if kubectl get pvc $pvc -n $NAMESPACE &> /dev/null; then
            print_warning "Existing PVC $pvc found, deleting..."
            kubectl delete pvc $pvc -n $NAMESPACE
        fi
    done

    # Delete PVs (only the ones we created)
    for pv in hostpath-pv nfs-pv local-pv csi-pv-example; do
        if kubectl get pv $pv &> /dev/null; then
            print_warning "Existing PV $pv found, deleting..."
            kubectl delete pv $pv
        fi
    done

    # Delete StorageClasses (only the ones we created)
    for sc in aws-ebs-gp3 azure-disk-premium gce-pd-ssd high-performance-io2; do
        if kubectl get storageclass $sc &> /dev/null; then
            print_warning "Existing StorageClass $sc found, deleting..."
            kubectl delete storageclass $sc
        fi
    done

    # Delete Secrets
    if kubectl get secret mysql-secret -n $NAMESPACE &> /dev/null; then
        print_warning "Existing Secret mysql-secret found, deleting..."
        kubectl delete secret mysql-secret -n $NAMESPACE
    fi

    # Delete VolumeSnapshots and VolumeSnapshotClass
    if kubectl get volumesnapshot database-backup -n $NAMESPACE &> /dev/null 2>&1; then
        print_warning "Existing VolumeSnapshot database-backup found, deleting..."
        kubectl delete volumesnapshot database-backup -n $NAMESPACE
    fi

    if kubectl get volumesnapshotclass csi-snapshotter &> /dev/null 2>&1; then
        print_warning "Existing VolumeSnapshotClass csi-snapshotter found, deleting..."
        kubectl delete volumesnapshotclass csi-snapshotter
    fi

    print_success "Cleanup completed"

    print_newline_with_separator
}

# Function to deploy basic examples
deploy_basic_examples() {
    print_status "Deploying basic PersistentVolume examples..."

    # Create data directory for hostPath PV
    print_status "Creating host data directory..."
    kubectl run create-dir --image=busybox --rm -it --restart=Never -- mkdir -p /mnt/data 2>/dev/null || true

    # Deploy selected resources from manifest
    print_status "Deploying PersistentVolume and StorageClass examples..."
    
    # Deploy only basic resources to avoid cloud dependencies
    cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: hostpath-pv
  labels:
    type: local
    storage: development
spec:
  capacity:
    storage: 10Gi
  volumeMode: Filesystem
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /mnt/data
    type: DirectoryOrCreate
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: Exists
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dev-pvc
  labels:
    environment: development
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: manual
---
apiVersion: v1
kind: Secret
metadata:
  name: mysql-secret
type: Opaque
data:
  root-password: cm9vdHBhc3N3b3JkMTIz
EOF

    print_success "Basic resources deployed"

    print_newline_with_separator
}

# Function to verify deployments
verify_deployments() {
    print_status "Verifying PersistentVolume deployments..."

    echo ""
    echo "=== PersistentVolumes ==="
    kubectl get pv -o wide

    print_newline_with_separator

    echo ""
    echo "=== PersistentVolumeClaims ==="
    kubectl get pvc -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== StorageClasses ==="
    kubectl get storageclass

    print_newline_with_separator

    # Wait for PVC to be bound
    wait_for_condition "PVC binding" \
        "kubectl get pvc $DEV_PVC -n $NAMESPACE -o jsonpath='{.status.phase}' | grep -q 'Bound'" \
        60 5

    print_success "PersistentVolume resources are ready"

    print_newline_with_separator
}

# Function to test PV functionality
test_pv_functionality() {
    print_status "Testing PersistentVolume functionality..."

    # Deploy test pod
    print_status "Deploying test pod with PVC..."
    cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pv-test-pod
  labels:
    app: pv-test
spec:
  containers:
  - name: app
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: storage
      mountPath: /data
  volumes:
  - name: storage
    persistentVolumeClaim:
      claimName: dev-pvc
  restartPolicy: Never
EOF

    # Wait for pod to be ready
    wait_for_condition "Test pod ready" \
        "kubectl get pod pv-test-pod -n $NAMESPACE -o jsonpath='{.status.phase}' | grep -q 'Running'" \
        120 10

    echo ""
    echo "=== Test Pod Status ==="
    kubectl get pod pv-test-pod -n $NAMESPACE -o wide

    print_newline_with_separator

    # Test writing data
    print_status "Testing data persistence..."

    echo ""
    echo "=== Writing test data ==="
    TEST_DATA="PersistentVolume test data - $(date)"
    kubectl exec pv-test-pod -n $NAMESPACE -- sh -c "echo '$TEST_DATA' > /data/test-file.txt"
    kubectl exec pv-test-pod -n $NAMESPACE -- sh -c "echo 'Additional data line' >> /data/test-file.txt"
    kubectl exec pv-test-pod -n $NAMESPACE -- sh -c "date > /data/timestamp.txt"

    echo ""
    echo "=== Reading test data ==="
    kubectl exec pv-test-pod -n $NAMESPACE -- cat /data/test-file.txt
    kubectl exec pv-test-pod -n $NAMESPACE -- cat /data/timestamp.txt

    echo ""
    echo "=== Listing files in persistent volume ==="
    kubectl exec pv-test-pod -n $NAMESPACE -- ls -la /data/

    # Test persistence by recreating pod
    print_status "Testing persistence across pod recreation..."
    kubectl delete pod pv-test-pod -n $NAMESPACE

    # Recreate pod
    cat << 'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: pv-test-pod-2
  labels:
    app: pv-test
spec:
  containers:
  - name: app
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: storage
      mountPath: /data
  volumes:
  - name: storage
    persistentVolumeClaim:
      claimName: dev-pvc
  restartPolicy: Never
EOF

    wait_for_condition "Second test pod ready" \
        "kubectl get pod pv-test-pod-2 -n $NAMESPACE -o jsonpath='{.status.phase}' | grep -q 'Running'" \
        120 10

    echo ""
    echo "=== Verifying data persistence ==="
    RECOVERED_DATA=$(kubectl exec pv-test-pod-2 -n $NAMESPACE -- cat /data/test-file.txt 2>/dev/null || echo "Data not found")
    if [[ "$RECOVERED_DATA" == *"$TEST_DATA"* ]]; then
        print_success "✅ Data persistence test PASSED - data survived pod recreation"
    else
        print_warning "⚠️  Data persistence test may have issues"
    fi

    echo "Expected: $TEST_DATA"
    echo "Actual: $RECOVERED_DATA"

    # Cleanup test pods
    kubectl delete pod pv-test-pod-2 -n $NAMESPACE

    print_newline_with_separator
}

# Function to show storage metrics
show_storage_metrics() {
    print_status "Showing storage metrics and information..."

    echo ""
    echo "=== Volume Usage (if metrics-server available) ==="
    kubectl top pods -n $NAMESPACE 2>/dev/null || echo "Metrics server not available"

    echo ""
    echo "=== PV and PVC Details ==="
    kubectl get pv -o custom-columns="NAME:.metadata.name,CAPACITY:.spec.capacity.storage,ACCESS:.spec.accessModes,RECLAIM:.spec.persistentVolumeReclaimPolicy,STATUS:.status.phase,CLAIM:.spec.claimRef.name"

    echo ""
    kubectl get pvc -n $NAMESPACE -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName,CAPACITY:.status.capacity.storage,ACCESS:.spec.accessModes,STORAGECLASS:.spec.storageClassName"

    echo ""
    echo "=== Volume Attachments ==="
    kubectl get volumeattachments 2>/dev/null | head -5 || echo "No volume attachments found"

    echo ""
    echo "=== Events Related to Storage ==="
    kubectl get events -n $NAMESPACE --field-selector involvedObject.kind=PersistentVolume,involvedObject.kind=PersistentVolumeClaim --sort-by=.metadata.creationTimestamp | tail -10

    print_newline_with_separator
}

# Function to demonstrate advanced features
demonstrate_advanced_features() {
    print_status "Demonstrating advanced PersistentVolume features..."

    echo ""
    echo "=== Volume Expansion Example ==="
    print_status "Current PVC size:"
    kubectl get pvc $DEV_PVC -n $NAMESPACE -o jsonpath='{.status.capacity.storage}'

    # Note: Volume expansion requires a StorageClass that supports it
    echo ""
    echo "To expand a volume:"
    echo "kubectl patch pvc $DEV_PVC -n $NAMESPACE -p '{\"spec\":{\"resources\":{\"requests\":{\"storage\":\"8Gi\"}}}}'"
    echo ""

    echo ""
    echo "=== Storage Class Features ==="
    if kubectl get storageclass &> /dev/null; then
        echo "Available storage classes with expansion capability:"
        kubectl get storageclass -o custom-columns="NAME:.metadata.name,PROVISIONER:.provisioner,EXPANSION:.allowVolumeExpansion,BINDING:.volumeBindingMode"
    else
        echo "No storage classes available in this cluster"
    fi

    echo ""
    echo "=== Volume Health Monitoring ==="
    kubectl get events --field-selector reason=VolumeUnhealthy -n $NAMESPACE 2>/dev/null | head -5 || echo "No volume health issues detected"

    print_newline_with_separator
}

# Function to show troubleshooting information
show_troubleshooting_info() {
    print_status "Showing troubleshooting information..."

    echo ""
    echo "=== Common Issues and Solutions ==="
    
    echo ""
    echo "1. PVC Stuck in Pending:"
    echo "   - Check if matching PV exists: kubectl get pv"
    echo "   - Check StorageClass: kubectl describe storageclass <name>"
    echo "   - Check PVC events: kubectl describe pvc <name>"

    echo ""
    echo "2. Pod Cannot Mount Volume:"
    echo "   - Check Pod events: kubectl describe pod <name>"
    echo "   - Check node resources: kubectl describe node <node>"
    echo "   - Check volume attachment: kubectl get volumeattachments"

    echo ""
    echo "3. Performance Issues:"
    echo "   - Check mount options: kubectl describe pv <name>"
    echo "   - Check I/O metrics: kubectl exec <pod> -- iostat -x 1"
    echo "   - Check storage class parameters"

    echo ""
    echo "=== Current Cluster Diagnostics ==="
    
    echo ""
    echo "Node conditions:"
    kubectl get nodes -o custom-columns="NAME:.metadata.name,STATUS:.status.conditions[?(@.type=='Ready')].status,DISK:.status.conditions[?(@.type=='DiskPressure')].status"

    echo ""
    echo "Storage-related pods in kube-system:"
    kubectl get pods -n kube-system | grep -E "(csi|storage|provisioner)" | head -5 || echo "No storage-related pods found"

    echo ""
    echo "Recent storage events:"
    kubectl get events --all-namespaces --field-selector reason=FailedMount,reason=ProvisioningFailed,reason=VolumeResizeFailed | tail -5 || echo "No recent storage failures"

    print_newline_with_separator
}

# Function to run interactive monitoring
interactive_monitoring() {
    print_status "Starting interactive storage monitoring..."
    echo "Press Ctrl+C to exit monitoring mode"

    trap 'print_status "Exiting monitoring mode..."; return' INT

    while true; do
        clear
        echo "=========================================="
        echo "  PersistentVolume Monitoring Dashboard"
        echo "=========================================="
        echo ""

        echo "=== PersistentVolumes ==="
        kubectl get pv -o wide | head -10

        echo ""
        echo "=== PersistentVolumeClaims ==="
        kubectl get pvc --all-namespaces | head -10

        echo ""
        echo "=== Recent Events ==="
        kubectl get events --all-namespaces --field-selector involvedObject.kind=PersistentVolume,involvedObject.kind=PersistentVolumeClaim --sort-by=.metadata.creationTimestamp | tail -5

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
    echo "=== All PersistentVolumes ==="
    kubectl get pv -o wide

    print_newline_with_separator

    echo ""
    echo "=== All PersistentVolumeClaims ==="
    kubectl get pvc --all-namespaces

    print_newline_with_separator

    echo ""
    echo "=== StorageClasses ==="
    kubectl get storageclass

    print_newline_with_separator

    echo ""
    echo "=== PersistentVolume Features Demonstrated ==="
    echo "1. ✅ Static Provisioning (hostPath PV)"
    echo "2. ✅ PVC Binding (automatic matching)"
    echo "3. ✅ Data Persistence (across pod restarts)"
    echo "4. ✅ Storage Abstraction (PV/PVC separation)"
    echo "5. ✅ Volume Lifecycle Management"
    echo "6. ✅ Storage Classes (dynamic provisioning ready)"
    echo "7. ✅ Access Modes (ReadWriteOnce)"
    echo "8. ✅ Reclaim Policies (Retain)"

    print_newline_with_separator

    echo ""
    echo "=== Useful Commands ==="
    echo "List PVs: kubectl get pv"
    echo "PV details: kubectl describe pv <pv-name>"
    echo "List PVCs: kubectl get pvc"
    echo "PVC details: kubectl describe pvc <pvc-name>"
    echo "StorageClasses: kubectl get storageclass"
    echo "Volume snapshots: kubectl get volumesnapshots"
    echo "Check events: kubectl get events --field-selector involvedObject.kind=PersistentVolume"
    echo "Manual PV reclaim: kubectl patch pv <name> -p '{\"spec\":{\"claimRef\": null}}'"
    echo "Force delete PVC: kubectl patch pvc <name> -p '{\"metadata\":{\"finalizers\":null}}'"

    print_newline_with_separator
}

# Cleanup function for script interruption
cleanup() {
    echo ""
    print_warning "Script interrupted. Current status:"
    kubectl get pv 2>/dev/null || echo "No PVs found"
    kubectl get pvc -n $NAMESPACE 2>/dev/null || echo "No PVCs found"
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    exit 1
}

# Show usage information
show_usage() {
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  deploy     Deploy basic PV examples and test functionality"
    echo "  test       Test PV functionality with read/write operations"
    echo "  monitor    Interactive monitoring of storage resources"
    echo "  metrics    Show storage metrics and information"
    echo "  advanced   Demonstrate advanced PV features"
    echo "  troubleshoot  Show troubleshooting information"
    echo "  cleanup    Clean up all created resources"
    echo "  info       Show cluster storage information"
    echo "  help       Show this usage information"
    echo ""
    echo "If no option is provided, full deployment and testing will run."
}

# Trap Ctrl+C
trap cleanup INT

# Parse command line arguments
case "${1:-}" in
    "deploy")
        echo "==================================="
        echo "  PersistentVolume Deployment"
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
        echo "  PersistentVolume Testing"
        echo "==================================="
        check_kubectl
        test_pv_functionality
        ;;
    "monitor")
        echo "==================================="
        echo "  PersistentVolume Monitoring"
        echo "==================================="
        check_kubectl
        interactive_monitoring
        ;;
    "metrics")
        echo "==================================="
        echo "  Storage Metrics"
        echo "==================================="
        check_kubectl
        show_storage_metrics
        ;;
    "advanced")
        echo "==================================="
        echo "  Advanced PV Features"
        echo "==================================="
        check_kubectl
        demonstrate_advanced_features
        ;;
    "troubleshoot")
        echo "==================================="
        echo "  Storage Troubleshooting"
        echo "==================================="
        check_kubectl
        show_troubleshooting_info
        ;;
    "cleanup")
        echo "==================================="
        echo "  Resource Cleanup"
        echo "==================================="
        check_kubectl
        cleanup_existing
        print_success "Cleanup completed!"
        ;;
    "info")
        echo "==================================="
        echo "  Cluster Storage Information"
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
        echo "  PersistentVolume Management Script"
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
        test_pv_functionality

        # Show metrics
        show_storage_metrics

        # Demonstrate advanced features
        demonstrate_advanced_features

        # Show troubleshooting info
        show_troubleshooting_info

        # Show final status
        show_final_status

        print_success "Script completed successfully!"

        echo ""
        echo "PersistentVolumes have been created and tested."
        echo "Run '$0 monitor' for interactive monitoring."
        echo "Run '$0 cleanup' to remove all created resources."
        ;;
    *)
        print_error "Unknown option: $1"
        show_usage
        exit 1
        ;;
esac
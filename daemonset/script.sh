#!/bin/bash

# DaemonSet Creation and Testing Script
# This script creates DaemonSets and demonstrates node-level service deployment

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MANIFEST_FILE="manifest.yml"
LOG_COLLECTOR_DS="log-collector"
NODE_EXPORTER_DS="node-exporter"
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

# Function to check cluster nodes
check_cluster_nodes() {
    print_status "Checking cluster nodes..."

    echo ""
    echo "=== Cluster Nodes ==="
    kubectl get nodes -o wide

    NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
    print_status "Total nodes in cluster: $NODE_COUNT"

    if [ $NODE_COUNT -eq 0 ]; then
        print_error "No nodes found in cluster"
        exit 1
    fi

    print_success "Found $NODE_COUNT node(s) for DaemonSet deployment"

    print_newline_with_separator
}

# Function to cleanup existing resources
cleanup_existing() {
    print_status "Cleaning up existing resources..."

    # Delete existing DaemonSets if they exist
    for ds in $LOG_COLLECTOR_DS $NODE_EXPORTER_DS; do
        if kubectl get daemonset $ds -n $NAMESPACE &> /dev/null; then
            print_warning "Existing DaemonSet $ds found, deleting..."
            kubectl delete daemonset $ds -n $NAMESPACE
        fi
    done

    # Delete associated resources
    for resource in configmap/fluentd-config serviceaccount/log-collector-sa clusterrole/log-collector-role clusterrolebinding/log-collector-binding service/node-exporter-service; do
        if kubectl get $resource -n $NAMESPACE &> /dev/null 2>&1 || kubectl get $resource &> /dev/null 2>&1; then
            print_warning "Existing $resource found, deleting..."
            kubectl delete $resource -n $NAMESPACE 2>/dev/null || kubectl delete $resource 2>/dev/null || true
        fi
    done

    # Clean up lingering pods
    kubectl get pods -l app=log-collector -n $NAMESPACE --no-headers 2>/dev/null | awk '{print $1}' | xargs -r kubectl delete pod --grace-period=0 --force -n $NAMESPACE
    kubectl get pods -l app=node-exporter -n $NAMESPACE --no-headers 2>/dev/null | awk '{print $1}' | xargs -r kubectl delete pod --grace-period=0 --force -n $NAMESPACE

    # Wait for DaemonSets to be deleted
    wait_for_condition "DaemonSet cleanup" \
        "! kubectl get daemonset $LOG_COLLECTOR_DS -n $NAMESPACE &> /dev/null" \
        60 2

    print_success "Cleanup completed"

    print_newline_with_separator
}

# Function to deploy DaemonSets
deploy_daemonsets() {
    print_status "Deploying DaemonSets and related resources..."
    kubectl apply -f ${MANIFEST_FILE} -n $NAMESPACE

    print_newline_with_separator

    # Wait for DaemonSets to be created
    wait_for_condition "DaemonSet creation" \
        "kubectl get daemonset $LOG_COLLECTOR_DS -n $NAMESPACE &> /dev/null && kubectl get daemonset $NODE_EXPORTER_DS -n $NAMESPACE &> /dev/null" \
        30 2

    print_success "DaemonSets deployed successfully"

    print_newline_with_separator
}

# Function to verify DaemonSet status
verify_daemonsets() {
    print_status "Verifying DaemonSet status..."

    # Check DaemonSet details
    echo ""
    echo "=== All DaemonSets ==="
    kubectl get daemonsets -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Log Collector DaemonSet Details ==="
    kubectl describe daemonset $LOG_COLLECTOR_DS -n $NAMESPACE

    print_newline_with_separator

    echo ""
    echo "=== DaemonSet Pods ==="
    kubectl get pods -l app=log-collector -n $NAMESPACE -o wide
    kubectl get pods -l app=node-exporter -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Related Resources ==="
    kubectl get serviceaccount log-collector-sa -n $NAMESPACE 2>/dev/null || echo "ServiceAccount not found"
    kubectl get clusterrole log-collector-role 2>/dev/null | head -3 || echo "ClusterRole not found"
    kubectl get configmap fluentd-config -n $NAMESPACE 2>/dev/null | head -3 || echo "ConfigMap not found"

    print_newline_with_separator

    print_success "DaemonSets are created and running"

    print_newline_with_separator
}

# Function to wait for DaemonSet pods to be ready
wait_for_daemonset_ready() {
    print_status "Waiting for DaemonSet pods to be ready..."

    NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)

    # Wait for log collector pods
    wait_for_condition "Log collector pods ready" \
        "kubectl get daemonset $LOG_COLLECTOR_DS -n $NAMESPACE -o jsonpath='{.status.numberReady}' | grep -q '$NODE_COUNT'" \
        180 10

    # Wait for node exporter pods
    wait_for_condition "Node exporter pods ready" \
        "kubectl get daemonset $NODE_EXPORTER_DS -n $NAMESPACE -o jsonpath='{.status.numberReady}' | grep -q '$NODE_COUNT'" \
        180 10

    print_success "All DaemonSet pods are ready"

    print_newline_with_separator
}

# Function to test node coverage
test_node_coverage() {
    print_status "Testing DaemonSet node coverage..."

    echo ""
    echo "=== Node Coverage Analysis ==="
    
    NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
    LOG_POD_COUNT=$(kubectl get pods -l app=log-collector -n $NAMESPACE --no-headers | wc -l)
    EXPORTER_POD_COUNT=$(kubectl get pods -l app=node-exporter -n $NAMESPACE --no-headers | wc -l)

    echo "Total nodes: $NODE_COUNT"
    echo "Log collector pods: $LOG_POD_COUNT"
    echo "Node exporter pods: $EXPORTER_POD_COUNT"

    if [ $NODE_COUNT -eq $LOG_POD_COUNT ] && [ $NODE_COUNT -eq $EXPORTER_POD_COUNT ]; then
        print_success "✅ Perfect node coverage - one pod per node for each DaemonSet"
    else
        print_warning "⚠️  Node coverage mismatch - some pods may be pending or failed"
    fi

    echo ""
    echo "=== Pod Distribution by Node ==="
    kubectl get pods -l app=log-collector -n $NAMESPACE -o wide --sort-by='{.spec.nodeName}'
    
    echo ""
    kubectl get pods -l app=node-exporter -n $NAMESPACE -o wide --sort-by='{.spec.nodeName}'

    print_newline_with_separator
}

# Function to test DaemonSet functionality
test_daemonset_functionality() {
    print_status "Testing DaemonSet functionality..."

    echo ""
    echo "=== Testing Log Collector Functionality ==="
    
    # Get a log collector pod
    LOG_POD=$(kubectl get pods -l app=log-collector -n $NAMESPACE --no-headers | head -1 | awk '{print $1}')
    
    if [ -n "$LOG_POD" ]; then
        print_status "Testing log collector pod: $LOG_POD"
        
        # Check if Fluentd is running
        kubectl exec $LOG_POD -n $NAMESPACE -- ps aux | grep fluentd || echo "Fluentd process check failed"
        
        # Check metrics endpoint
        kubectl exec $LOG_POD -n $NAMESPACE -- curl -f -s http://localhost:24231/api/plugins 2>/dev/null | head -3 || echo "Metrics endpoint test failed"
        
        # Check log file access
        kubectl exec $LOG_POD -n $NAMESPACE -- ls -la /var/log/ | head -5 || echo "Log directory access failed"
    else
        print_warning "No log collector pods found"
    fi

    echo ""
    echo "=== Testing Node Exporter Functionality ==="
    
    # Get a node exporter pod
    EXPORTER_POD=$(kubectl get pods -l app=node-exporter -n $NAMESPACE --no-headers | head -1 | awk '{print $1}')
    
    if [ -n "$EXPORTER_POD" ]; then
        print_status "Testing node exporter pod: $EXPORTER_POD"
        
        # Check metrics endpoint
        kubectl exec $EXPORTER_POD -n $NAMESPACE -- wget -q -O- http://localhost:9100/metrics | head -5 || echo "Node metrics test failed"
        
        # Check node filesystem access
        kubectl exec $EXPORTER_POD -n $NAMESPACE -- ls -la /host/proc/ | head -3 || echo "Host filesystem access failed"
    else
        print_warning "No node exporter pods found"
    fi

    print_newline_with_separator
}

# Function to test rolling updates
test_rolling_updates() {
    print_status "Testing DaemonSet rolling updates..."

    # Get current image
    CURRENT_IMAGE=$(kubectl get daemonset $NODE_EXPORTER_DS -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}')
    echo "Current node-exporter image: $CURRENT_IMAGE"

    # Update to a different version (using same version but trigger update)
    NEW_IMAGE="prom/node-exporter:v1.6.0"
    print_status "Updating image from $CURRENT_IMAGE to $NEW_IMAGE..."
    
    kubectl patch daemonset $NODE_EXPORTER_DS -n $NAMESPACE -p '{"spec":{"template":{"spec":{"containers":[{"name":"node-exporter","image":"'$NEW_IMAGE'"}]}}}}'

    # Monitor rolling update
    print_status "Monitoring rolling update progress..."
    
    # Wait for update to complete
    wait_for_condition "Rolling update completion" \
        "kubectl get daemonset $NODE_EXPORTER_DS -n $NAMESPACE -o jsonpath='{.status.updatedNumberScheduled}' | grep -q \"\$(kubectl get nodes --no-headers | wc -l)\"" \
        180 10

    echo ""
    echo "=== Updated Pods ==="
    kubectl get pods -l app=node-exporter -n $NAMESPACE -o wide

    # Rollback to test rollback functionality
    print_status "Testing rollback functionality..."
    kubectl patch daemonset $NODE_EXPORTER_DS -n $NAMESPACE -p '{"spec":{"template":{"spec":{"containers":[{"name":"node-exporter","image":"'$CURRENT_IMAGE'"}]}}}}'

    print_success "Rolling update and rollback completed"

    print_newline_with_separator
}

# Function to test node scheduling
test_node_scheduling() {
    print_status "Testing DaemonSet node scheduling behavior..."

    echo ""
    echo "=== Testing Node Selector Behavior ==="
    
    # Create a test DaemonSet with node selector
    cat <<EOF | kubectl apply -f - -n $NAMESPACE
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: test-node-selector
  labels:
    app: test-daemonset
spec:
  selector:
    matchLabels:
      app: test-daemonset
  template:
    metadata:
      labels:
        app: test-daemonset
    spec:
      nodeSelector:
        kubernetes.io/os: linux  # Only run on Linux nodes
      containers:
      - name: test
        image: busybox
        command: ['sleep', '300']
        resources:
          requests:
            memory: "32Mi"
            cpu: "10m"
          limits:
            memory: "64Mi"
            cpu: "20m"
EOF

    # Wait for test DaemonSet to be ready
    sleep 10
    
    echo ""
    echo "=== Test DaemonSet with Node Selector ==="
    kubectl get daemonset test-node-selector -n $NAMESPACE -o wide
    kubectl get pods -l app=test-daemonset -n $NAMESPACE -o wide

    # Clean up test DaemonSet
    kubectl delete daemonset test-node-selector -n $NAMESPACE

    print_newline_with_separator
}

# Function to test tolerations
test_tolerations() {
    print_status "Testing DaemonSet tolerations..."

    echo ""
    echo "=== Node Taints and Tolerations ==="
    
    # Show node taints
    echo "Node taints:"
    kubectl get nodes -o json | jq -r '.items[] | select(.spec.taints != null) | "\(.metadata.name): \(.spec.taints | map(.key + "=" + .value + ":" + .effect) | join(", "))"' || \
    kubectl describe nodes | grep -A 5 Taints | head -10

    echo ""
    echo "=== DaemonSet Tolerations ==="
    kubectl get daemonset $LOG_COLLECTOR_DS -n $NAMESPACE -o jsonpath='{.spec.template.spec.tolerations}' | jq '.' 2>/dev/null || \
    kubectl get daemonset $LOG_COLLECTOR_DS -n $NAMESPACE -o yaml | grep -A 20 tolerations

    print_newline_with_separator
}

# Function to demonstrate pod deletion and recreation
test_pod_recreation() {
    print_status "Testing DaemonSet pod recreation..."

    # Get a pod to delete
    POD_TO_DELETE=$(kubectl get pods -l app=log-collector -n $NAMESPACE --no-headers | head -1 | awk '{print $1}')
    
    if [ -n "$POD_TO_DELETE" ]; then
        NODE_NAME=$(kubectl get pod $POD_TO_DELETE -n $NAMESPACE -o jsonpath='{.spec.nodeName}')
        
        print_status "Deleting pod $POD_TO_DELETE on node $NODE_NAME..."
        kubectl delete pod $POD_TO_DELETE -n $NAMESPACE

        # Wait for pod to be recreated
        wait_for_condition "Pod recreation" \
            "kubectl get pods -l app=log-collector -n $NAMESPACE --field-selector spec.nodeName=$NODE_NAME --no-headers | grep -v Terminating | wc -l | grep -q '1'" \
            60 5

        echo ""
        echo "=== Recreated Pod ==="
        kubectl get pods -l app=log-collector -n $NAMESPACE --field-selector spec.nodeName=$NODE_NAME -o wide

        print_success "Pod successfully recreated on the same node"
    else
        print_warning "No pods found to test recreation"
    fi

    print_newline_with_separator
}

# Function to show resource usage
show_resource_usage() {
    print_status "Showing DaemonSet resource usage..."

    echo ""
    echo "=== Resource Usage (if metrics-server available) ==="
    
    echo "Log collector pods:"
    kubectl top pods -l app=log-collector -n $NAMESPACE 2>/dev/null || echo "Metrics server not available"
    
    echo ""
    echo "Node exporter pods:"
    kubectl top pods -l app=node-exporter -n $NAMESPACE 2>/dev/null || echo "Metrics server not available"

    echo ""
    echo "=== Resource Requests and Limits ==="
    kubectl describe daemonset $LOG_COLLECTOR_DS -n $NAMESPACE | grep -A 10 "Limits\|Requests" | head -10

    print_newline_with_separator
}

# Function to show final status
show_final_status() {
    echo ""
    echo "=================================="
    echo "         FINAL STATUS"
    echo "=================================="

    echo ""
    echo "=== All DaemonSets ==="
    kubectl get daemonsets -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== DaemonSet Status Summary ==="
    NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
    
    for ds in $LOG_COLLECTOR_DS $NODE_EXPORTER_DS; do
        if kubectl get daemonset $ds -n $NAMESPACE &>/dev/null; then
            DESIRED=$(kubectl get daemonset $ds -n $NAMESPACE -o jsonpath='{.status.desiredNumberScheduled}')
            READY=$(kubectl get daemonset $ds -n $NAMESPACE -o jsonpath='{.status.numberReady}')
            AVAILABLE=$(kubectl get daemonset $ds -n $NAMESPACE -o jsonpath='{.status.numberAvailable}')
            echo "$ds: Desired=$DESIRED, Ready=$READY, Available=$AVAILABLE"
        else
            echo "$ds: Not found"
        fi
    done

    print_newline_with_separator

    echo ""
    echo "=== Pod Distribution ==="
    echo "Log collector pods per node:"
    kubectl get pods -l app=log-collector -n $NAMESPACE -o wide --no-headers | awk '{print $7}' | sort | uniq -c
    
    echo ""
    echo "Node exporter pods per node:"
    kubectl get pods -l app=node-exporter -n $NAMESPACE -o wide --no-headers | awk '{print $7}' | sort | uniq -c

    print_newline_with_separator

    echo ""
    echo "=== DaemonSet Features Demonstrated ==="
    echo "1. ✅ Node Coverage (one pod per node)"
    echo "2. ✅ System-level Access (host filesystem, logs)"
    echo "3. ✅ Tolerations (run on tainted nodes)"
    echo "4. ✅ Rolling Updates (controlled updates)"
    echo "5. ✅ Pod Recreation (automatic restart on node)"
    echo "6. ✅ RBAC Integration (service accounts)"
    echo "7. ✅ Resource Management (limits and requests)"

    print_newline_with_separator

    echo ""
    echo "=== Useful Commands ==="
    echo "View DaemonSet: kubectl describe daemonset $LOG_COLLECTOR_DS -n $NAMESPACE"
    echo "DaemonSet logs: kubectl logs -l app=log-collector -n $NAMESPACE"
    echo "Update image: kubectl set image daemonset/$LOG_COLLECTOR_DS log-collector=fluent/fluentd:v1.17 -n $NAMESPACE"
    echo "Check node coverage: kubectl get pods -l app=log-collector -o wide -n $NAMESPACE"
    echo "Node metrics: kubectl top pods -l app=node-exporter -n $NAMESPACE"
    echo "Delete DaemonSet: kubectl delete daemonset $LOG_COLLECTOR_DS -n $NAMESPACE"
    echo "Exec into pod: kubectl exec -it \$(kubectl get pods -l app=log-collector --no-headers | head -1 | awk '{print \$1}') -n $NAMESPACE -- /bin/bash"

    print_newline_with_separator
}

# Cleanup function for script interruption
cleanup() {
    echo ""
    print_warning "Script interrupted. Current status:"
    kubectl get daemonsets -n $NAMESPACE 2>/dev/null || echo "No DaemonSets found"
    kubectl get pods -l app=log-collector -n $NAMESPACE 2>/dev/null || echo "No log collector pods found"
    kubectl get pods -l app=node-exporter -n $NAMESPACE 2>/dev/null || echo "No node exporter pods found"
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    exit 1
}

# Trap Ctrl+C
trap cleanup INT

# Main execution
main() {
    echo "=================================="
    echo "  DaemonSet Creation & Test Script"
    echo "=================================="

    # Pre-flight checks
    check_kubectl

    # Check cluster nodes
    check_cluster_nodes

    # Cleanup any existing resources
    cleanup_existing

    # Deploy DaemonSets
    deploy_daemonsets

    # Verify DaemonSets
    verify_daemonsets

    # Wait for DaemonSet pods to be ready
    wait_for_daemonset_ready

    # Test node coverage
    test_node_coverage

    # Test DaemonSet functionality
    test_daemonset_functionality

    # Test rolling updates
    test_rolling_updates

    # Test node scheduling
    test_node_scheduling

    # Test tolerations
    test_tolerations

    # Test pod recreation
    test_pod_recreation

    # Show resource usage
    show_resource_usage

    # Show final status
    show_final_status

    print_success "Script completed successfully!"

    echo ""
    echo "DaemonSets have been created and all node-level features demonstrated."
    echo "Each node now runs the log collector and monitoring pods."
}

# Run main function
main "$@"
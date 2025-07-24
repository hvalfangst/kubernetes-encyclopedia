#!/bin/bash

# NetworkPolicy Example Deployment Script
# This script demonstrates deploying and testing NetworkPolicies for a three-tier web application

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="netpol-demo"
MANIFEST_FILE="manifest.yml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

wait_for_pods() {
    local namespace=$1
    local label_selector=$2
    local timeout=${3:-300}
    
    log_info "Waiting for pods with selector '$label_selector' to be ready..."
    if kubectl wait --for=condition=ready pod -l "$label_selector" -n "$namespace" --timeout="${timeout}s" > /dev/null 2>&1; then
        log_success "Pods are ready"
    else
        log_error "Pods failed to become ready within ${timeout}s"
        return 1
    fi
}

test_connectivity() {
    local from_pod=$1
    local to_service=$2
    local port=$3
    local should_succeed=$4
    local timeout=${5:-5}
    
    log_info "Testing connectivity: $from_pod -> $to_service:$port"
    
    if kubectl exec -n "$NAMESPACE" "$from_pod" -- timeout "$timeout" nc -zv "$to_service" "$port" > /dev/null 2>&1; then
        if [ "$should_succeed" = "true" ]; then
            log_success "✓ Connection successful (expected)"
        else
            log_error "✗ Connection successful (should have failed)"
            return 1
        fi
    else
        if [ "$should_succeed" = "false" ]; then
            log_success "✓ Connection failed (expected)"
        else
            log_error "✗ Connection failed (should have succeeded)"
            return 1
        fi
    fi
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if we can connect to cluster
    if ! kubectl cluster-info > /dev/null 2>&1; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    # Check if manifest file exists
    if [ ! -f "$SCRIPT_DIR/$MANIFEST_FILE" ]; then
        log_error "Manifest file not found: $SCRIPT_DIR/$MANIFEST_FILE"
        exit 1
    fi
    
    # Check if CNI supports NetworkPolicies
    log_info "Checking if CNI supports NetworkPolicies..."
    # This is a basic check - some CNIs might not expose this information
    if kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.containerRuntimeVersion}' | grep -q containerd; then
        log_warning "Make sure your CNI plugin supports NetworkPolicies (Calico, Cilium, Weave Net, etc.)"
    fi
    
    log_success "Prerequisites check completed"
}

deploy_application() {
    log_info "Deploying NetworkPolicy example application..."
    
    # Apply the manifest
    kubectl apply -f "$SCRIPT_DIR/$MANIFEST_FILE"
    
    log_success "Application deployed"
    
    # Wait for deployments to be ready
    log_info "Waiting for deployments to be ready..."
    kubectl wait --for=condition=available deployment/frontend -n "$NAMESPACE" --timeout=300s
    kubectl wait --for=condition=available deployment/backend -n "$NAMESPACE" --timeout=300s
    kubectl wait --for=condition=available deployment/database -n "$NAMESPACE" --timeout=300s
    
    # Wait for pods to be ready
    wait_for_pods "$NAMESPACE" "tier=frontend" 300
    wait_for_pods "$NAMESPACE" "tier=backend" 300
    wait_for_pods "$NAMESPACE" "tier=database" 300
    wait_for_pods "$NAMESPACE" "role=testing" 60
    
    log_success "All pods are ready"
}

test_network_policies() {
    log_info "Testing NetworkPolicy enforcement..."
    
    # Get pod names
    local test_pod=$(kubectl get pod -n "$NAMESPACE" -l role=testing -o jsonpath='{.items[0].metadata.name}')
    local frontend_pod=$(kubectl get pod -n "$NAMESPACE" -l tier=frontend -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$test_pod" ] || [ -z "$frontend_pod" ]; then
        log_error "Could not find required pods for testing"
        return 1
    fi
    
    log_info "Using test pod: $test_pod"
    log_info "Using frontend pod: $frontend_pod"
    
    echo ""
    log_info "=== Testing Network Policy Rules ==="
    echo ""
    
    # Test 1: Test pod should NOT be able to reach backend directly (blocked by policy)
    log_info "Test 1: Test pod -> Backend (should FAIL due to network policy)"
    test_connectivity "$test_pod" "backend-service" "8080" "false" 3
    
    # Test 2: Test pod should NOT be able to reach database directly (blocked by policy)
    log_info "Test 2: Test pod -> Database (should FAIL due to network policy)"
    test_connectivity "$test_pod" "database-service" "5432" "false" 3
    
    # Test 3: Test pod should be able to reach frontend (allowed by policy)
    log_info "Test 3: Test pod -> Frontend (should SUCCEED)"
    test_connectivity "$test_pod" "frontend-service" "80" "true" 5
    
    # Test 4: Frontend should be able to reach backend (allowed by policy)
    log_info "Test 4: Frontend -> Backend (should SUCCEED)"
    test_connectivity "$frontend_pod" "backend-service" "8080" "true" 5
    
    # Test 5: DNS should work (allowed by egress rules)
    log_info "Test 5: DNS resolution test"
    if kubectl exec -n "$NAMESPACE" "$test_pod" -- nslookup kubernetes.default.svc.cluster.local > /dev/null 2>&1; then
        log_success "✓ DNS resolution works"
    else
        log_error "✗ DNS resolution failed"
        return 1
    fi
    
    echo ""
    log_success "Network policy tests completed successfully!"
}

show_status() {
    log_info "Showing deployment status..."
    
    echo ""
    echo "=== Namespace ==="
    kubectl get namespace "$NAMESPACE" --show-labels
    
    echo ""
    echo "=== Deployments ==="
    kubectl get deployments -n "$NAMESPACE" -o wide
    
    echo ""
    echo "=== Pods ==="
    kubectl get pods -n "$NAMESPACE" -o wide --show-labels
    
    echo ""
    echo "=== Services ==="
    kubectl get services -n "$NAMESPACE" -o wide
    
    echo ""
    echo "=== NetworkPolicies ==="
    kubectl get networkpolicy -n "$NAMESPACE" -o wide
    
    echo ""
    echo "=== NetworkPolicy Details ==="
    for policy in $(kubectl get networkpolicy -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}'); do
        echo "--- $policy ---"
        kubectl describe networkpolicy "$policy" -n "$NAMESPACE"
        echo ""
    done
}

cleanup() {
    log_info "Cleaning up resources..."
    
    if kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
        kubectl delete namespace "$NAMESPACE" --wait=true
        log_success "Cleanup completed"
    else
        log_info "Namespace $NAMESPACE does not exist, nothing to clean up"
    fi
}

show_help() {
    echo "NetworkPolicy Example Deployment Script"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  deploy    Deploy the NetworkPolicy example application"
    echo "  test      Test NetworkPolicy enforcement (requires deployed application)"
    echo "  status    Show current deployment status"
    echo "  cleanup   Remove all deployed resources"
    echo "  help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 deploy           # Deploy the application"
    echo "  $0 test             # Test network policies"
    echo "  $0 status           # Show deployment status"
    echo "  $0 cleanup          # Clean up resources"
    echo ""
    echo "Note: Make sure your Kubernetes cluster has a CNI plugin that supports NetworkPolicies"
    echo "      (such as Calico, Cilium, Weave Net, etc.)"
}

# Main script logic
main() {
    case "${1:-deploy}" in
        "deploy")
            check_prerequisites
            deploy_application
            log_success "Deployment completed! Run '$0 test' to test NetworkPolicies"
            ;;
        "test")
            if ! kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
                log_error "Namespace $NAMESPACE not found. Run '$0 deploy' first."
                exit 1
            fi
            test_network_policies
            ;;
        "status")
            if ! kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
                log_error "Namespace $NAMESPACE not found. Run '$0 deploy' first."
                exit 1
            fi
            show_status
            ;;
        "cleanup")
            cleanup
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log_error "Unknown command: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
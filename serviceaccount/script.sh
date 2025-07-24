#!/bin/bash

# ServiceAccount Example Deployment Script
# This script demonstrates deploying and testing ServiceAccounts with RBAC

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="serviceaccount-demo"
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

test_rbac_permissions() {
    local serviceaccount=$1
    local namespace=$2
    local resource=$3
    local verb=$4
    local should_succeed=$5
    
    log_info "Testing RBAC: $serviceaccount can $verb $resource"
    
    if kubectl auth can-i "$verb" "$resource" --as="system:serviceaccount:$namespace:$serviceaccount" -n "$namespace" > /dev/null 2>&1; then
        if [ "$should_succeed" = "true" ]; then
            log_success "✓ Permission granted (expected)"
        else
            log_error "✗ Permission granted (should have been denied)"
            return 1
        fi
    else
        if [ "$should_succeed" = "false" ]; then
            log_success "✓ Permission denied (expected)"
        else
            log_error "✗ Permission denied (should have been granted)"
            return 1
        fi
    fi
}

check_token_mount() {
    local pod_name=$1
    local namespace=$2
    local should_have_token=$3
    
    log_info "Checking token mount for pod: $pod_name"
    
    if kubectl exec -n "$namespace" "$pod_name" -- test -f /var/run/secrets/kubernetes.io/serviceaccount/token > /dev/null 2>&1; then
        if [ "$should_have_token" = "true" ]; then
            log_success "✓ Token mounted (expected)"
        else
            log_error "✗ Token mounted (should not be mounted)"
            return 1
        fi
    else
        if [ "$should_have_token" = "false" ]; then
            log_success "✓ Token not mounted (expected)"
        else
            log_error "✗ Token not mounted (should be mounted)"
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
    
    # Check RBAC is enabled
    if ! kubectl auth can-i create clusterrole > /dev/null 2>&1; then
        log_warning "May not have sufficient permissions to create RBAC resources"
    fi
    
    log_success "Prerequisites check completed"
}

deploy_application() {
    log_info "Deploying ServiceAccount RBAC example..."
    
    # Apply the manifest
    kubectl apply -f "$SCRIPT_DIR/$MANIFEST_FILE"
    
    log_success "ServiceAccount RBAC example deployed"
    
    # Wait for deployments to be ready
    log_info "Waiting for deployment to be ready..."
    kubectl wait --for=condition=available deployment/api-client-deployment -n "$NAMESPACE" --timeout=300s
    
    # Wait for pods to be ready
    wait_for_pods "$NAMESPACE" "app=demo" 300
    wait_for_pods "$NAMESPACE" "app=api-client" 60
    
    log_success "All pods are ready"
}

test_serviceaccount_rbac() {
    log_info "Testing ServiceAccount RBAC permissions..."
    
    echo ""
    log_info "=== Testing RBAC Permissions ==="
    echo ""
    
    # Test pod-reader ServiceAccount
    log_info "Testing pod-reader ServiceAccount permissions..."
    test_rbac_permissions "pod-reader" "$NAMESPACE" "pods" "get" "true"
    test_rbac_permissions "pod-reader" "$NAMESPACE" "pods" "list" "true"
    test_rbac_permissions "pod-reader" "$NAMESPACE" "configmaps" "get" "false"
    test_rbac_permissions "pod-reader" "$NAMESPACE" "deployments" "get" "false"
    
    echo ""
    
    # Test config-manager ServiceAccount
    log_info "Testing config-manager ServiceAccount permissions..."
    test_rbac_permissions "config-manager" "$NAMESPACE" "configmaps" "get" "true"
    test_rbac_permissions "config-manager" "$NAMESPACE" "configmaps" "create" "true"
    test_rbac_permissions "config-manager" "$NAMESPACE" "configmaps" "delete" "true"
    test_rbac_permissions "config-manager" "$NAMESPACE" "pods" "get" "false"
    test_rbac_permissions "config-manager" "$NAMESPACE" "deployments" "get" "false"
    
    echo ""
    
    # Test deployment-manager ServiceAccount
    log_info "Testing deployment-manager ServiceAccount permissions..."
    test_rbac_permissions "deployment-manager" "$NAMESPACE" "deployments" "get" "true"
    test_rbac_permissions "deployment-manager" "$NAMESPACE" "deployments" "create" "true"
    test_rbac_permissions "deployment-manager" "$NAMESPACE" "pods" "get" "true"
    test_rbac_permissions "deployment-manager" "$NAMESPACE" "configmaps" "get" "false"
    
    echo ""
    
    # Test cross-namespace-reader ServiceAccount (cluster-wide)
    log_info "Testing cross-namespace-reader ServiceAccount permissions..."
    kubectl auth can-i get pods --as="system:serviceaccount:$NAMESPACE:cross-namespace-reader" --all-namespaces > /dev/null 2>&1 && \
        log_success "✓ Cross-namespace pod read access granted" || \
        log_error "✗ Cross-namespace pod read access denied"
        
    kubectl auth can-i get services --as="system:serviceaccount:$NAMESPACE:cross-namespace-reader" --all-namespaces > /dev/null 2>&1 && \
        log_success "✓ Cross-namespace service read access granted" || \
        log_error "✗ Cross-namespace service read access denied"
        
    kubectl auth can-i get deployments --as="system:serviceaccount:$NAMESPACE:cross-namespace-reader" --all-namespaces > /dev/null 2>&1 && \
        log_error "✗ Cross-namespace deployment access granted (should be denied)" || \
        log_success "✓ Cross-namespace deployment access denied (expected)"
    
    echo ""
    log_success "RBAC permission tests completed!"
}

test_token_mounting() {
    log_info "Testing ServiceAccount token mounting..."
    
    echo ""
    log_info "=== Testing Token Mounting ==="
    echo ""
    
    # Get pod names
    local pod_reader_pod=$(kubectl get pods -n "$NAMESPACE" -l serviceaccount=pod-reader -o jsonpath='{.items[0].metadata.name}')
    local config_manager_pod=$(kubectl get pods -n "$NAMESPACE" -l serviceaccount=config-manager -o jsonpath='{.items[0].metadata.name}')
    local no_api_access_pod=$(kubectl get pods -n "$NAMESPACE" -l serviceaccount=no-api-access -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$pod_reader_pod" ] || [ -z "$config_manager_pod" ] || [ -z "$no_api_access_pod" ]; then
        log_error "Could not find required pods for token mounting tests"
        return 1
    fi
    
    # Test token mounting
    check_token_mount "$pod_reader_pod" "$NAMESPACE" "true"
    check_token_mount "$config_manager_pod" "$NAMESPACE" "true"
    check_token_mount "$no_api_access_pod" "$NAMESPACE" "false"
    
    echo ""
    log_success "Token mounting tests completed!"
}

test_api_access() {
    log_info "Testing API access from pods..."
    
    echo ""
    log_info "=== Testing API Access ==="
    echo ""
    
    # Get pod names
    local pod_reader_pod=$(kubectl get pods -n "$NAMESPACE" -l serviceaccount=pod-reader -o jsonpath='{.items[0].metadata.name}')
    local config_manager_pod=$(kubectl get pods -n "$NAMESPACE" -l serviceaccount=config-manager -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$pod_reader_pod" ] || [ -z "$config_manager_pod" ]; then
        log_error "Could not find required pods for API access tests"
        return 1
    fi
    
    # Test pod-reader can access pods
    log_info "Testing pod-reader API access to pods..."
    if kubectl exec -n "$NAMESPACE" "$pod_reader_pod" -- kubectl get pods -n "$NAMESPACE" > /dev/null 2>&1; then
        log_success "✓ pod-reader can access pods via API"
    else
        log_error "✗ pod-reader cannot access pods via API"
    fi
    
    # Test pod-reader cannot access configmaps
    log_info "Testing pod-reader API access to configmaps (should fail)..."
    if ! kubectl exec -n "$NAMESPACE" "$pod_reader_pod" -- kubectl get configmaps -n "$NAMESPACE" > /dev/null 2>&1; then
        log_success "✓ pod-reader cannot access configmaps (expected)"
    else
        log_error "✗ pod-reader can access configmaps (unexpected)"
    fi
    
    # Test config-manager can access configmaps
    log_info "Testing config-manager API access to configmaps..."
    if kubectl exec -n "$NAMESPACE" "$config_manager_pod" -- kubectl get configmaps -n "$NAMESPACE" > /dev/null 2>&1; then
        log_success "✓ config-manager can access configmaps via API"
    else
        log_error "✗ config-manager cannot access configmaps via API"
    fi
    
    # Test config-manager can create configmaps
    log_info "Testing config-manager can create configmaps..."
    if kubectl exec -n "$NAMESPACE" "$config_manager_pod" -- kubectl create configmap test-config-from-pod --from-literal=test=value -n "$NAMESPACE" > /dev/null 2>&1; then
        log_success "✓ config-manager can create configmaps via API"
        # Clean up
        kubectl delete configmap test-config-from-pod -n "$NAMESPACE" > /dev/null 2>&1 || true
    else
        log_error "✗ config-manager cannot create configmaps via API"
    fi
    
    echo ""
    log_success "API access tests completed!"
}

show_status() {
    log_info "Showing ServiceAccount RBAC deployment status..."
    
    echo ""
    echo "=== Namespace ==="
    kubectl get namespace "$NAMESPACE" --show-labels
    
    echo ""
    echo "=== ServiceAccounts ==="
    kubectl get serviceaccounts -n "$NAMESPACE" -o wide
    
    echo ""
    echo "=== Roles ==="
    kubectl get roles -n "$NAMESPACE" -o wide
    
    echo ""
    echo "=== ClusterRoles (demo-related) ==="
    kubectl get clusterroles | grep -E "(cross-namespace-reader|demo)" || echo "No demo-related ClusterRoles found"
    
    echo ""
    echo "=== RoleBindings ==="
    kubectl get rolebindings -n "$NAMESPACE" -o wide
    
    echo ""
    echo "=== ClusterRoleBindings (demo-related) ==="
    kubectl get clusterrolebindings | grep -E "(cross-namespace-reader|demo)" || echo "No demo-related ClusterRoleBindings found"
    
    echo ""
    echo "=== Pods ==="
    kubectl get pods -n "$NAMESPACE" -o wide --show-labels
    
    echo ""
    echo "=== Deployments ==="
    kubectl get deployments -n "$NAMESPACE" -o wide
    
    echo ""
    echo "=== Services ==="
    kubectl get services -n "$NAMESPACE" -o wide
    
    echo ""
    echo "=== ConfigMaps ==="
    kubectl get configmaps -n "$NAMESPACE" -o wide
    
    echo ""
    echo "=== ServiceAccount Details ==="
    for sa in $(kubectl get serviceaccounts -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}'); do
        if [ "$sa" != "default" ]; then
            echo "--- ServiceAccount: $sa ---"
            kubectl describe serviceaccount "$sa" -n "$NAMESPACE"
            echo ""
            echo "Effective permissions for $sa:"
            kubectl auth can-i --list --as="system:serviceaccount:$NAMESPACE:$sa" -n "$NAMESPACE" | head -10
            echo ""
        fi
    done
}

show_pod_logs() {
    log_info "Showing pod logs for demonstration..."
    
    echo ""
    echo "=== Pod Logs ==="
    
    for pod in $(kubectl get pods -n "$NAMESPACE" -l app=demo -o jsonpath='{.items[*].metadata.name}'); do
        echo ""
        echo "--- Logs for $pod ---"
        kubectl logs "$pod" -n "$NAMESPACE" --tail=20 || echo "Failed to get logs for $pod"
    done
}

cleanup() {
    log_info "Cleaning up resources..."
    
    if kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
        # Clean up ClusterRoleBinding first
        kubectl delete clusterrolebinding cross-namespace-reader-binding > /dev/null 2>&1 || true
        kubectl delete clusterrole cross-namespace-reader-role > /dev/null 2>&1 || true
        
        # Delete namespace (this will clean up everything else)
        kubectl delete namespace "$NAMESPACE" --wait=true
        log_success "Cleanup completed"
    else
        log_info "Namespace $NAMESPACE does not exist, nothing to clean up"
    fi
}

show_help() {
    echo "ServiceAccount RBAC Example Deployment Script"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  deploy       Deploy the ServiceAccount RBAC example"
    echo "  test-rbac    Test RBAC permissions (requires deployed application)"
    echo "  test-tokens  Test ServiceAccount token mounting"
    echo "  test-api     Test API access from pods"
    echo "  test-all     Run all tests"
    echo "  logs         Show pod logs"
    echo "  status       Show current deployment status"
    echo "  cleanup      Remove all deployed resources"
    echo "  help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 deploy           # Deploy the RBAC example"
    echo "  $0 test-all         # Run all tests"
    echo "  $0 status           # Show deployment status"
    echo "  $0 cleanup          # Clean up resources"
    echo ""
    echo "The example demonstrates:"
    echo "  - Different ServiceAccounts with specific permissions"
    echo "  - RBAC Roles and RoleBindings"
    echo "  - Cross-namespace access with ClusterRoles"
    echo "  - Token mounting control"
    echo "  - API access from pods"
}

# Main script logic
main() {
    case "${1:-deploy}" in
        "deploy")
            check_prerequisites
            deploy_application
            log_success "Deployment completed! Run '$0 test-all' to test ServiceAccount RBAC"
            ;;
        "test-rbac")
            if ! kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
                log_error "Namespace $NAMESPACE not found. Run '$0 deploy' first."
                exit 1
            fi
            test_serviceaccount_rbac
            ;;
        "test-tokens")
            if ! kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
                log_error "Namespace $NAMESPACE not found. Run '$0 deploy' first."
                exit 1
            fi
            test_token_mounting
            ;;
        "test-api")
            if ! kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
                log_error "Namespace $NAMESPACE not found. Run '$0 deploy' first."
                exit 1
            fi
            test_api_access
            ;;
        "test-all")
            if ! kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
                log_error "Namespace $NAMESPACE not found. Run '$0 deploy' first."
                exit 1
            fi
            test_serviceaccount_rbac
            test_token_mounting
            test_api_access
            ;;
        "logs")
            if ! kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
                log_error "Namespace $NAMESPACE not found. Run '$0 deploy' first."
                exit 1
            fi
            show_pod_logs
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
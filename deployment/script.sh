#!/bin/bash

# Deployment Creation and Testing Script
# This script creates a Deployment, verifies it's running, scales it, and demonstrates rollout features

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MANIFEST_FILE="manifest.yml"
DEPLOYMENT_NAME="nginx-deployment"
NAMESPACE="default"
APP_LABEL="nginx"

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

# Function to cleanup existing resources
cleanup_existing() {
    print_status "Cleaning up existing resources..."

    # Delete existing Deployment if it exists
    if kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE &> /dev/null; then
        print_warning "Existing Deployment found, deleting..."
        kubectl delete deployment $DEPLOYMENT_NAME -n $NAMESPACE

        # Wait for Deployment to be deleted
        wait_for_condition "Deployment deletion" \
            "! kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE &> /dev/null" \
            60 2
    fi

    # Delete any existing pods from this deployment
    if kubectl get pods -l app=$APP_LABEL -n $NAMESPACE --no-headers 2>/dev/null | grep -q .; then
        print_warning "Existing pods found, waiting for cleanup..."
        kubectl delete pods -l app=$APP_LABEL -n $NAMESPACE --grace-period=30
    fi

    print_success "Cleanup completed"

    print_newline_with_separator
}

# Function to deploy Deployment
deploy_deployment() {
    print_status "Deploying Deployment..."
    kubectl apply -f ${MANIFEST_FILE} -n $NAMESPACE

    print_newline_with_separator

    # Wait for Deployment to be created
    wait_for_condition "Deployment creation" \
        "kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE &> /dev/null" \
        30 2

    print_success "Deployment created successfully"

    print_newline_with_separator
}

# Function to verify Deployment status
verify_deployment() {
    print_status "Verifying Deployment status..."

    # Wait for Deployment to be ready
    wait_for_condition "Deployment ready" \
        "kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' | grep -q '3'" \
        120 5

    # Check Deployment details
    echo ""
    echo "=== Deployment Details ==="
    kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== ReplicaSet Details ==="
    kubectl get rs -l app=$APP_LABEL -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Pod Details ==="
    kubectl get pods -l app=$APP_LABEL -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Deployment Description ==="
    kubectl describe deployment $DEPLOYMENT_NAME -n $NAMESPACE

    print_newline_with_separator

    print_success "Deployment is running and ready"

    print_newline_with_separator
}

# Function to test scaling
test_scaling() {
    print_status "Testing Deployment scaling..."

    # Scale up to 5 replicas
    print_status "Scaling up to 5 replicas..."
    kubectl scale deployment $DEPLOYMENT_NAME --replicas=5 -n $NAMESPACE

    # Wait for scale up
    wait_for_condition "Scale up to 5 replicas" \
        "kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' | grep -q '5'" \
        120 5

    echo ""
    echo "=== Scaled Deployment ==="
    kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Scaled Pods ==="
    kubectl get pods -l app=$APP_LABEL -n $NAMESPACE -o wide

    print_newline_with_separator

    # Scale down to 2 replicas
    print_status "Scaling down to 2 replicas..."
    kubectl scale deployment $DEPLOYMENT_NAME --replicas=2 -n $NAMESPACE

    # Wait for scale down
    wait_for_condition "Scale down to 2 replicas" \
        "kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' | grep -q '2'" \
        120 5

    echo ""
    echo "=== Scaled Down Deployment ==="
    kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Remaining Pods ==="
    kubectl get pods -l app=$APP_LABEL -n $NAMESPACE -o wide

    print_newline_with_separator

    print_success "Scaling test completed successfully"

    print_newline_with_separator
}

# Function to test rolling update
test_rolling_update() {
    print_status "Testing rolling update..."

    # Update the image to trigger a rolling update
    print_status "Updating nginx image to 1.22..."
    kubectl set image deployment/$DEPLOYMENT_NAME nginx-container=nginx:1.22 -n $NAMESPACE

    # Monitor rollout status
    print_status "Monitoring rollout progress..."
    kubectl rollout status deployment/$DEPLOYMENT_NAME -n $NAMESPACE --timeout=180s

    echo ""
    echo "=== Updated Deployment ==="
    kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Updated Pods ==="
    kubectl get pods -l app=$APP_LABEL -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Rollout History ==="
    kubectl rollout history deployment/$DEPLOYMENT_NAME -n $NAMESPACE

    print_newline_with_separator

    print_success "Rolling update completed successfully"

    print_newline_with_separator
}

# Function to test rollback
test_rollback() {
    print_status "Testing rollback functionality..."

    # Rollback to previous version
    print_status "Rolling back to previous version..."
    kubectl rollout undo deployment/$DEPLOYMENT_NAME -n $NAMESPACE

    # Monitor rollback status
    print_status "Monitoring rollback progress..."
    kubectl rollout status deployment/$DEPLOYMENT_NAME -n $NAMESPACE --timeout=180s

    echo ""
    echo "=== Rolled Back Deployment ==="
    kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Rolled Back Pods ==="
    kubectl get pods -l app=$APP_LABEL -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Updated Rollout History ==="
    kubectl rollout history deployment/$DEPLOYMENT_NAME -n $NAMESPACE

    print_newline_with_separator

    print_success "Rollback completed successfully"

    print_newline_with_separator
}

# Function to test pod connectivity
test_connectivity() {
    print_status "Testing Pod connectivity..."

    # Get one of the pod names
    POD_NAME=$(kubectl get pods -l app=$APP_LABEL -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}')

    if [ -z "$POD_NAME" ]; then
        print_error "No pods found for connectivity test"
        return 1
    fi

    print_status "Testing HTTP connectivity to pod: $POD_NAME"

    # Port forward to test connectivity
    kubectl port-forward pod/$POD_NAME 8080:80 -n $NAMESPACE &
    PORT_FORWARD_PID=$!

    # Give port-forward time to establish
    sleep 5

    # Test HTTP connection
    if curl -f -s http://localhost:8080 > /dev/null; then
        print_success "HTTP connectivity test passed"
    else
        print_warning "HTTP connectivity test failed"
    fi

    # Clean up port forward
    kill $PORT_FORWARD_PID 2>/dev/null || true

    print_newline_with_separator
}

# Function to show final status
show_final_status() {
    echo ""
    echo "=================================="
    echo "         FINAL STATUS"
    echo "=================================="

    echo ""
    echo "=== Deployment Status ==="
    kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== ReplicaSet Status ==="
    kubectl get rs -l app=$APP_LABEL -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Pod Status ==="
    kubectl get pods -l app=$APP_LABEL -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Resource Usage (if metrics-server available) ==="
    kubectl top pods -l app=$APP_LABEL -n $NAMESPACE 2>/dev/null || echo "Metrics server not available"

    print_newline_with_separator

    echo ""
    echo "=== Deployment Events ==="
    kubectl get events --field-selector involvedObject.name=$DEPLOYMENT_NAME -n $NAMESPACE --sort-by=.metadata.creationTimestamp

    print_newline_with_separator

    echo ""
    echo "=== Useful Commands ==="
    echo "View Deployment: kubectl describe deployment $DEPLOYMENT_NAME -n $NAMESPACE"
    echo "Scale Deployment: kubectl scale deployment $DEPLOYMENT_NAME --replicas=<number> -n $NAMESPACE"
    echo "Update image: kubectl set image deployment/$DEPLOYMENT_NAME nginx-container=nginx:<version> -n $NAMESPACE"
    echo "Check rollout: kubectl rollout status deployment/$DEPLOYMENT_NAME -n $NAMESPACE"
    echo "Rollback: kubectl rollout undo deployment/$DEPLOYMENT_NAME -n $NAMESPACE"
    echo "View logs: kubectl logs -l app=$APP_LABEL -n $NAMESPACE"
    echo "Delete Deployment: kubectl delete deployment $DEPLOYMENT_NAME -n $NAMESPACE"

    print_newline_with_separator
}

# Cleanup function for script interruption
cleanup() {
    echo ""
    print_warning "Script interrupted. Current status:"
    kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE 2>/dev/null || echo "Deployment not found"
    kubectl get pods -l app=$APP_LABEL -n $NAMESPACE 2>/dev/null || echo "No pods found"
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    exit 1
}

# Trap Ctrl+C
trap cleanup INT

# Main execution
main() {
    echo "=================================="
    echo "  Deployment Creation & Test Script"
    echo "=================================="

    # Pre-flight checks
    check_kubectl

    # Cleanup any existing resources
    cleanup_existing

    # Deploy Deployment
    deploy_deployment

    # Verify deployment
    verify_deployment

    # Test scaling
    test_scaling

    # Test rolling update
    test_rolling_update

    # Test rollback
    test_rollback

    # Test connectivity
    test_connectivity

    # Show final status
    show_final_status

    print_success "Script completed successfully!"

    echo ""
    echo "The Deployment is now running and ready for use."
    echo "You can interact with it using the commands shown above."
}

# Run main function
main "$@"
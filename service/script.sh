#!/bin/bash

# Service Creation and Testing Script
# This script creates Services, tests connectivity, and demonstrates different service types

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MANIFEST_FILE="manifest.yml"
DEPLOYMENT_FILE="../deployment/manifest.yml"
SERVICE_NAME="nginx-service"
LB_SERVICE_NAME="nginx-loadbalancer"
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

    # Delete existing Services if they exist
    if kubectl get service $SERVICE_NAME -n $NAMESPACE &> /dev/null; then
        print_warning "Existing ClusterIP Service found, deleting..."
        kubectl delete service $SERVICE_NAME -n $NAMESPACE
    fi

    if kubectl get service $LB_SERVICE_NAME -n $NAMESPACE &> /dev/null; then
        print_warning "Existing LoadBalancer Service found, deleting..."
        kubectl delete service $LB_SERVICE_NAME -n $NAMESPACE
    fi

    # Wait for services to be deleted
    wait_for_condition "Service cleanup" \
        "! kubectl get service $SERVICE_NAME -n $NAMESPACE &> /dev/null && ! kubectl get service $LB_SERVICE_NAME -n $NAMESPACE &> /dev/null" \
        30 2

    print_success "Cleanup completed"

    print_newline_with_separator
}

# Function to ensure deployment exists
ensure_deployment() {
    print_status "Ensuring target deployment exists..."

    if ! kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE &> /dev/null; then
        print_warning "Target deployment not found, creating it..."
        
        if [ -f "$DEPLOYMENT_FILE" ]; then
            kubectl apply -f $DEPLOYMENT_FILE -n $NAMESPACE
            
            # Wait for deployment to be ready
            wait_for_condition "Deployment ready" \
                "kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' | grep -q '3'" \
                120 5
                
            print_success "Deployment created and ready"
        else
            print_error "Deployment manifest file not found: $DEPLOYMENT_FILE"
            print_status "Creating a simple deployment for testing..."
            
            # Create a simple deployment for testing
            cat <<EOF | kubectl apply -f - -n $NAMESPACE
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEPLOYMENT_NAME
  labels:
    app: $APP_LABEL
spec:
  replicas: 3
  selector:
    matchLabels:
      app: $APP_LABEL
      tier: frontend
  template:
    metadata:
      labels:
        app: $APP_LABEL
        tier: frontend
    spec:
      containers:
      - name: nginx
        image: nginx:1.21
        ports:
        - containerPort: 80
        - containerPort: 9090
EOF
            
            wait_for_condition "Test deployment ready" \
                "kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' | grep -q '3'" \
                120 5
        fi
    else
        print_success "Target deployment already exists"
    fi

    print_newline_with_separator
}

# Function to deploy Services
deploy_services() {
    print_status "Deploying Services..."
    kubectl apply -f ${MANIFEST_FILE} -n $NAMESPACE

    print_newline_with_separator

    # Wait for Services to be created
    wait_for_condition "ClusterIP Service creation" \
        "kubectl get service $SERVICE_NAME -n $NAMESPACE &> /dev/null" \
        30 2

    wait_for_condition "LoadBalancer Service creation" \
        "kubectl get service $LB_SERVICE_NAME -n $NAMESPACE &> /dev/null" \
        30 2

    print_success "Services deployed successfully"

    print_newline_with_separator
}

# Function to verify Service status
verify_services() {
    print_status "Verifying Service status..."

    # Check Service details
    echo ""
    echo "=== ClusterIP Service Details ==="
    kubectl get service $SERVICE_NAME -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== LoadBalancer Service Details ==="
    kubectl get service $LB_SERVICE_NAME -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Service Endpoints ==="
    kubectl get endpoints -l app=$APP_LABEL -n $NAMESPACE

    print_newline_with_separator

    echo ""
    echo "=== ClusterIP Service Description ==="
    kubectl describe service $SERVICE_NAME -n $NAMESPACE

    print_newline_with_separator

    echo ""
    echo "=== LoadBalancer Service Description ==="
    kubectl describe service $LB_SERVICE_NAME -n $NAMESPACE

    print_newline_with_separator

    print_success "Services are running and configured"

    print_newline_with_separator
}

# Function to test DNS resolution
test_dns_resolution() {
    print_status "Testing DNS resolution..."

    # Test internal DNS resolution
    print_status "Testing internal service DNS resolution..."
    
    kubectl run dns-test --image=busybox --rm -it --restart=Never -- \
        nslookup $SERVICE_NAME.$NAMESPACE.svc.cluster.local 2>/dev/null | grep -E "(Name:|Address:)" || \
        print_warning "DNS resolution test failed"

    print_newline_with_separator
}

# Function to test service connectivity
test_connectivity() {
    print_status "Testing Service connectivity..."

    # Test ClusterIP service connectivity
    print_status "Testing ClusterIP service connectivity..."
    
    CLUSTER_IP=$(kubectl get service $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.clusterIP}')
    print_status "ClusterIP: $CLUSTER_IP"

    # Test HTTP connectivity
    kubectl run connectivity-test --image=curlimages/curl --rm -it --restart=Never -- \
        curl -f -s http://$SERVICE_NAME.$NAMESPACE.svc.cluster.local/ -o /dev/null && \
        print_success "ClusterIP service HTTP connectivity test passed" || \
        print_warning "ClusterIP service HTTP connectivity test failed"

    print_newline_with_separator

    # Test LoadBalancer service if external IP is available
    print_status "Testing LoadBalancer service..."
    
    EXTERNAL_IP=$(kubectl get service $LB_SERVICE_NAME -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    EXTERNAL_HOSTNAME=$(kubectl get service $LB_SERVICE_NAME -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    
    if [ -n "$EXTERNAL_IP" ]; then
        print_status "LoadBalancer External IP: $EXTERNAL_IP"
        print_status "Testing external connectivity (this may take a moment)..."
        
        # Test from within cluster
        kubectl run lb-test --image=curlimages/curl --rm -it --restart=Never -- \
            curl -f -s http://$EXTERNAL_IP/ -o /dev/null && \
            print_success "LoadBalancer external IP connectivity test passed" || \
            print_warning "LoadBalancer external IP connectivity test failed"
            
    elif [ -n "$EXTERNAL_HOSTNAME" ]; then
        print_status "LoadBalancer External Hostname: $EXTERNAL_HOSTNAME"
        print_status "Testing external connectivity via hostname..."
        
        kubectl run lb-hostname-test --image=curlimages/curl --rm -it --restart=Never -- \
            curl -f -s http://$EXTERNAL_HOSTNAME/ -o /dev/null && \
            print_success "LoadBalancer hostname connectivity test passed" || \
            print_warning "LoadBalancer hostname connectivity test failed"
    else
        print_warning "LoadBalancer external IP/hostname not yet assigned (this is normal for some cloud providers)"
        print_status "You can check later with: kubectl get service $LB_SERVICE_NAME -n $NAMESPACE"
    fi

    print_newline_with_separator
}

# Function to test load balancing
test_load_balancing() {
    print_status "Testing load balancing across Pods..."

    # Get Pod IPs for verification
    echo ""
    echo "=== Target Pod Information ==="
    kubectl get pods -l app=$APP_LABEL -n $NAMESPACE -o wide

    print_newline_with_separator

    # Test load balancing by making multiple requests
    print_status "Making multiple requests to test load distribution..."
    
    for i in {1..5}; do
        echo "Request $i:"
        kubectl run load-test-$i --image=curlimages/curl --rm --restart=Never -- \
            curl -s http://$SERVICE_NAME.$NAMESPACE.svc.cluster.local/ | head -n 1 || \
            echo "Request $i failed"
        sleep 1
    done

    print_success "Load balancing test completed"

    print_newline_with_separator
}

# Function to test different port access
test_port_access() {
    print_status "Testing multi-port service access..."

    # Test HTTP port (80)
    print_status "Testing HTTP port (80)..."
    kubectl run http-port-test --image=curlimages/curl --rm -it --restart=Never -- \
        curl -f -s http://$SERVICE_NAME.$NAMESPACE.svc.cluster.local:80/ -o /dev/null && \
        print_success "HTTP port (80) accessible" || \
        print_warning "HTTP port (80) not accessible"

    # Test metrics port (9090) - this will likely fail since nginx doesn't serve on 9090 by default
    print_status "Testing metrics port (9090)..."
    kubectl run metrics-port-test --image=curlimages/curl --rm -it --restart=Never -- \
        curl -f -s http://$SERVICE_NAME.$NAMESPACE.svc.cluster.local:9090/ -o /dev/null && \
        print_success "Metrics port (9090) accessible" || \
        print_warning "Metrics port (9090) not accessible (expected - nginx doesn't serve on 9090)"

    print_newline_with_separator
}

# Function to demonstrate service discovery
demonstrate_service_discovery() {
    print_status "Demonstrating service discovery methods..."

    # Environment variables
    print_status "Creating test Pod to show environment variables..."
    kubectl run env-test --image=busybox --restart=Never -- sleep 3600

    # Wait for pod to be ready
    wait_for_condition "Test Pod ready" \
        "kubectl get pod env-test -n $NAMESPACE -o jsonpath='{.status.phase}' | grep -q 'Running'" \
        60 5

    echo ""
    echo "=== Environment Variables for Service Discovery ==="
    kubectl exec env-test -n $NAMESPACE -- env | grep -E "${SERVICE_NAME^^}" | head -10 || \
        echo "No environment variables found (Pod may have been created before Service)"

    print_newline_with_separator

    # DNS resolution
    echo ""
    echo "=== DNS Resolution for Service Discovery ==="
    kubectl exec env-test -n $NAMESPACE -- nslookup $SERVICE_NAME 2>/dev/null | grep -E "(Name:|Address:)" || \
        echo "DNS resolution failed"

    # Cleanup test pod
    kubectl delete pod env-test -n $NAMESPACE --grace-period=0 --force &> /dev/null

    print_newline_with_separator
}

# Function to show final status
show_final_status() {
    echo ""
    echo "=================================="
    echo "         FINAL STATUS"
    echo "=================================="

    echo ""
    echo "=== All Services ==="
    kubectl get services -l app=$APP_LABEL -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Service Endpoints ==="
    kubectl get endpoints -l app=$APP_LABEL -n $NAMESPACE

    print_newline_with_separator

    echo ""
    echo "=== Target Pods ==="
    kubectl get pods -l app=$APP_LABEL -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Service Events ==="
    kubectl get events --field-selector involvedObject.name=$SERVICE_NAME -n $NAMESPACE --sort-by=.metadata.creationTimestamp | tail -10

    print_newline_with_separator

    echo ""
    echo "=== LoadBalancer Service Status ==="
    EXTERNAL_IP=$(kubectl get service $LB_SERVICE_NAME -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    EXTERNAL_HOSTNAME=$(kubectl get service $LB_SERVICE_NAME -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
    
    if [ -n "$EXTERNAL_IP" ]; then
        echo "External IP: $EXTERNAL_IP"
        echo "Access URL: http://$EXTERNAL_IP/"
    elif [ -n "$EXTERNAL_HOSTNAME" ]; then
        echo "External Hostname: $EXTERNAL_HOSTNAME"
        echo "Access URL: http://$EXTERNAL_HOSTNAME/"
    else
        echo "External IP/Hostname: Pending (check with cloud provider)"
    fi

    print_newline_with_separator

    echo ""
    echo "=== Useful Commands ==="
    echo "View ClusterIP Service: kubectl describe service $SERVICE_NAME -n $NAMESPACE"
    echo "View LoadBalancer Service: kubectl describe service $LB_SERVICE_NAME -n $NAMESPACE"
    echo "Check endpoints: kubectl get endpoints -l app=$APP_LABEL -n $NAMESPACE"
    echo "Test connectivity: kubectl run test --image=curlimages/curl --rm -it -- curl http://$SERVICE_NAME/"
    echo "Port forward: kubectl port-forward service/$SERVICE_NAME 8080:80"
    echo "Delete services: kubectl delete service $SERVICE_NAME $LB_SERVICE_NAME -n $NAMESPACE"

    print_newline_with_separator
}

# Cleanup function for script interruption
cleanup() {
    echo ""
    print_warning "Script interrupted. Current status:"
    kubectl get services -l app=$APP_LABEL -n $NAMESPACE 2>/dev/null || echo "No services found"
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
    echo "  Service Creation & Test Script"
    echo "=================================="

    # Pre-flight checks
    check_kubectl

    # Cleanup any existing resources
    cleanup_existing

    # Ensure target deployment exists
    ensure_deployment

    # Deploy Services
    deploy_services

    # Verify services
    verify_services

    # Test DNS resolution
    test_dns_resolution

    # Test connectivity
    test_connectivity

    # Test load balancing
    test_load_balancing

    # Test port access
    test_port_access

    # Demonstrate service discovery
    demonstrate_service_discovery

    # Show final status
    show_final_status

    print_success "Script completed successfully!"

    echo ""
    echo "Services are now running and ready for use."
    echo "You can interact with them using the commands shown above."
}

# Run main function
main "$@"
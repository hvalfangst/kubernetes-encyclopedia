#!/bin/bash

# Ingress Creation and Testing Script
# This script creates Ingress resources, tests routing, and demonstrates different ingress configurations

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MANIFEST_FILE="manifest.yml"
SERVICE_FILE="../service/manifest.yml"
DEPLOYMENT_FILE="../deployment/manifest.yml"
INGRESS_NAME="nginx-ingress"
NODEPORT_INGRESS_NAME="nginx-nodeport-ingress"
SERVICE_NAME="nginx-service"
DEPLOYMENT_NAME="nginx-deployment"
NAMESPACE="default"
APP_LABEL="nginx"
TEST_HOST="demo.example.com"
API_HOST="api.demo.example.com"
NODEPORT_HOST="nodeport.demo.local"

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

# Function to check ingress controller
check_ingress_controller() {
    print_status "Checking for Ingress Controller..."

    # Check for common ingress controllers
    if kubectl get pods -n ingress-nginx --no-headers 2>/dev/null | grep -q ingress-nginx-controller; then
        print_success "NGINX Ingress Controller found"
        INGRESS_CONTROLLER="nginx"
    elif kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -q ingress; then
        print_success "Ingress Controller found in kube-system"
        INGRESS_CONTROLLER="generic"
    else
        print_warning "No Ingress Controller detected"
        print_status "Note: You may need to install an Ingress Controller first"
        print_status "For NGINX: kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml"
        INGRESS_CONTROLLER="none"
    fi

    # Check IngressClass
    if kubectl get ingressclass --no-headers 2>/dev/null | grep -q nginx; then
        print_success "IngressClass 'nginx' available"
    else
        print_warning "IngressClass 'nginx' not found - may affect Ingress functionality"
    fi

    print_newline_with_separator
}

# Function to cleanup existing resources
cleanup_existing() {
    print_status "Cleaning up existing resources..."

    # Delete existing Ingresses if they exist
    if kubectl get ingress $INGRESS_NAME -n $NAMESPACE &> /dev/null; then
        print_warning "Existing main Ingress found, deleting..."
        kubectl delete ingress $INGRESS_NAME -n $NAMESPACE
    fi

    if kubectl get ingress $NODEPORT_INGRESS_NAME -n $NAMESPACE &> /dev/null; then
        print_warning "Existing NodePort Ingress found, deleting..."
        kubectl delete ingress $NODEPORT_INGRESS_NAME -n $NAMESPACE
    fi

    # Wait for ingresses to be deleted
    wait_for_condition "Ingress cleanup" \
        "! kubectl get ingress $INGRESS_NAME -n $NAMESPACE &> /dev/null && ! kubectl get ingress $NODEPORT_INGRESS_NAME -n $NAMESPACE &> /dev/null" \
        30 2

    print_success "Cleanup completed"

    print_newline_with_separator
}

# Function to ensure backend resources exist
ensure_backend_resources() {
    print_status "Ensuring backend resources exist..."

    # Check and create deployment if needed
    if ! kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE &> /dev/null; then
        print_warning "Target deployment not found, creating it..."
        
        if [ -f "$DEPLOYMENT_FILE" ]; then
            kubectl apply -f $DEPLOYMENT_FILE -n $NAMESPACE
        else
            print_status "Creating basic deployment for testing..."
            cat <<EOF | kubectl apply -f - -n $NAMESPACE
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEPLOYMENT_NAME
  labels:
    app: $APP_LABEL
spec:
  replicas: 2
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
EOF
        fi
        
        wait_for_condition "Deployment ready" \
            "kubectl get deployment $DEPLOYMENT_NAME -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' | grep -q '2'" \
            120 5
    else
        print_success "Deployment already exists"
    fi

    # Check and create service if needed
    if ! kubectl get service $SERVICE_NAME -n $NAMESPACE &> /dev/null; then
        print_warning "Target service not found, creating it..."
        
        if [ -f "$SERVICE_FILE" ]; then
            kubectl apply -f $SERVICE_FILE -n $NAMESPACE
        else
            print_status "Creating basic service for testing..."
            cat <<EOF | kubectl apply -f - -n $NAMESPACE
apiVersion: v1
kind: Service
metadata:
  name: $SERVICE_NAME
  labels:
    app: $APP_LABEL
spec:
  type: ClusterIP
  selector:
    app: $APP_LABEL
    tier: frontend
  ports:
  - name: http
    protocol: TCP
    port: 80
    targetPort: 80
EOF
        fi
        
        wait_for_condition "Service ready" \
            "kubectl get service $SERVICE_NAME -n $NAMESPACE &> /dev/null" \
            30 2
    else
        print_success "Service already exists"
    fi

    print_newline_with_separator
}

# Function to create TLS secret for testing
create_tls_secret() {
    print_status "Creating TLS secret for testing..."

    if kubectl get secret demo-tls -n $NAMESPACE &> /dev/null; then
        print_status "TLS secret already exists"
        return 0
    fi

    # Create a self-signed certificate for testing
    print_status "Generating self-signed certificate..."
    
    # Create temporary directory for certificates
    CERT_DIR=$(mktemp -d)
    
    # Generate private key
    openssl genrsa -out $CERT_DIR/tls.key 2048 2>/dev/null
    
    # Generate certificate signing request
    cat > $CERT_DIR/cert.conf <<EOF
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
C = US
ST = Demo
L = Demo
O = Demo
CN = demo.example.com

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = demo.example.com
DNS.2 = api.demo.example.com
DNS.3 = *.demo.example.com
EOF
    
    # Generate certificate
    openssl req -new -x509 -key $CERT_DIR/tls.key -out $CERT_DIR/tls.crt -days 365 -config $CERT_DIR/cert.conf -extensions v3_req 2>/dev/null
    
    # Create Kubernetes secret
    kubectl create secret tls demo-tls \
        --cert=$CERT_DIR/tls.crt \
        --key=$CERT_DIR/tls.key \
        -n $NAMESPACE
    
    # Cleanup temporary files
    rm -rf $CERT_DIR
    
    print_success "TLS secret created"

    print_newline_with_separator
}

# Function to deploy Ingresses
deploy_ingresses() {
    print_status "Deploying Ingress resources..."
    kubectl apply -f ${MANIFEST_FILE} -n $NAMESPACE

    print_newline_with_separator

    # Wait for Ingresses to be created
    wait_for_condition "Main Ingress creation" \
        "kubectl get ingress $INGRESS_NAME -n $NAMESPACE &> /dev/null" \
        30 2

    wait_for_condition "NodePort Ingress creation" \
        "kubectl get ingress $NODEPORT_INGRESS_NAME -n $NAMESPACE &> /dev/null" \
        30 2

    print_success "Ingress resources deployed successfully"

    print_newline_with_separator
}

# Function to verify Ingress status
verify_ingresses() {
    print_status "Verifying Ingress status..."

    # Check Ingress details
    echo ""
    echo "=== Main Ingress Details ==="
    kubectl get ingress $INGRESS_NAME -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== NodePort Ingress Details ==="
    kubectl get ingress $NODEPORT_INGRESS_NAME -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Main Ingress Description ==="
    kubectl describe ingress $INGRESS_NAME -n $NAMESPACE

    print_newline_with_separator

    echo ""
    echo "=== Ingress Controller Status ==="
    if [ "$INGRESS_CONTROLLER" = "nginx" ]; then
        kubectl get pods -n ingress-nginx | grep controller || \
        echo "NGINX Ingress Controller not found in ingress-nginx namespace"
    else
        echo "Generic or no ingress controller detected"
    fi

    print_newline_with_separator

    print_success "Ingress resources are configured"

    print_newline_with_separator
}

# Function to get ingress IP
get_ingress_ip() {
    print_status "Determining Ingress access point..."

    # Try to get LoadBalancer IP
    INGRESS_IP=$(kubectl get ingress $INGRESS_NAME -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    INGRESS_HOSTNAME=$(kubectl get ingress $INGRESS_NAME -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

    if [ -n "$INGRESS_IP" ]; then
        print_success "Ingress IP: $INGRESS_IP"
        ACCESS_POINT="$INGRESS_IP"
    elif [ -n "$INGRESS_HOSTNAME" ]; then
        print_success "Ingress Hostname: $INGRESS_HOSTNAME"
        ACCESS_POINT="$INGRESS_HOSTNAME"
    else
        # Try to get service IP/NodePort
        if [ "$INGRESS_CONTROLLER" = "nginx" ]; then
            CONTROLLER_IP=$(kubectl get service -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
            CONTROLLER_HOSTNAME=$(kubectl get service -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
            
            if [ -n "$CONTROLLER_IP" ]; then
                print_success "Controller LoadBalancer IP: $CONTROLLER_IP"
                ACCESS_POINT="$CONTROLLER_IP"
            elif [ -n "$CONTROLLER_HOSTNAME" ]; then
                print_success "Controller LoadBalancer Hostname: $CONTROLLER_HOSTNAME"
                ACCESS_POINT="$CONTROLLER_HOSTNAME"
            else
                # Get NodePort
                NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null)
                if [ -z "$NODE_IP" ]; then
                    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
                fi
                NODE_PORT=$(kubectl get service -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null)
                
                if [ -n "$NODE_IP" ] && [ -n "$NODE_PORT" ]; then
                    print_success "NodePort access: $NODE_IP:$NODE_PORT"
                    ACCESS_POINT="$NODE_IP:$NODE_PORT"
                else
                    print_warning "Could not determine Ingress access point"
                    ACCESS_POINT=""
                fi
            fi
        else
            print_warning "Could not determine access point - Ingress Controller may not be properly configured"
            ACCESS_POINT=""
        fi
    fi

    print_newline_with_separator
}

# Function to test ingress routing
test_ingress_routing() {
    print_status "Testing Ingress routing..."

    if [ -z "$ACCESS_POINT" ]; then
        print_warning "No access point available - skipping routing tests"
        return 1
    fi

    # Test main host routing
    print_status "Testing main host routing ($TEST_HOST)..."
    
    kubectl run ingress-test-main --image=curlimages/curl --rm -it --restart=Never -- \
        curl -f -s -H "Host: $TEST_HOST" http://$ACCESS_POINT/ -o /dev/null && \
        print_success "Main host routing test passed" || \
        print_warning "Main host routing test failed"

    # Test API host routing
    print_status "Testing API host routing ($API_HOST)..."
    
    kubectl run ingress-test-api --image=curlimages/curl --rm -it --restart=Never -- \
        curl -f -s -H "Host: $API_HOST" http://$ACCESS_POINT/v1 -o /dev/null && \
        print_success "API host routing test passed" || \
        print_warning "API host routing test failed"

    # Test health endpoint
    print_status "Testing health endpoint..."
    
    kubectl run ingress-test-health --image=curlimages/curl --rm -it --restart=Never -- \
        curl -f -s -H "Host: $API_HOST" http://$ACCESS_POINT/health -o /dev/null && \
        print_success "Health endpoint test passed" || \
        print_warning "Health endpoint test failed (expected - nginx doesn't have /health by default)"

    print_newline_with_separator
}

# Function to test HTTPS/TLS
test_https() {
    print_status "Testing HTTPS/TLS functionality..."

    if [ -z "$ACCESS_POINT" ]; then
        print_warning "No access point available - skipping HTTPS tests"
        return 1
    fi

    # Test HTTPS connection (will fail with self-signed cert but shows TLS is working)
    print_status "Testing HTTPS connection with self-signed certificate..."
    
    kubectl run https-test --image=curlimages/curl --rm -it --restart=Never -- \
        curl -k -f -s -H "Host: $TEST_HOST" https://$ACCESS_POINT/ -o /dev/null && \
        print_success "HTTPS connection test passed (ignoring certificate validation)" || \
        print_warning "HTTPS connection test failed"

    print_newline_with_separator
}

# Function to demonstrate path-based routing
demonstrate_path_routing() {
    print_status "Demonstrating path-based routing..."

    if [ -z "$ACCESS_POINT" ]; then
        print_warning "No access point available - skipping path routing demo"
        return 1
    fi

    echo ""
    echo "=== Path Routing Examples ==="
    echo "Main site (/):"
    kubectl run path-test-root --image=curlimages/curl --rm --restart=Never -- \
        curl -s -H "Host: $TEST_HOST" http://$ACCESS_POINT/ | head -n 3 2>/dev/null || echo "Failed to access root path"

    echo ""
    echo "API v1 (/v1):"
    kubectl run path-test-v1 --image=curlimages/curl --rm --restart=Never -- \
        curl -s -H "Host: $API_HOST" http://$ACCESS_POINT/v1 | head -n 3 2>/dev/null || echo "Failed to access /v1 path"

    print_newline_with_separator
}

# Function to show final status
show_final_status() {
    echo ""
    echo "=================================="
    echo "         FINAL STATUS"
    echo "=================================="

    echo ""
    echo "=== All Ingress Resources ==="
    kubectl get ingress -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== TLS Secrets ==="
    kubectl get secrets -n $NAMESPACE | grep tls || echo "No TLS secrets found"

    print_newline_with_separator

    echo ""
    echo "=== Backend Services ==="
    kubectl get services -l app=$APP_LABEL -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Ingress Controller Status ==="
    if [ "$INGRESS_CONTROLLER" = "nginx" ]; then
        kubectl get pods -n ingress-nginx | grep controller || echo "NGINX controller not found"
        kubectl get service -n ingress-nginx ingress-nginx-controller || echo "NGINX service not found"
    fi

    print_newline_with_separator

    echo ""
    echo "=== Access Information ==="
    if [ -n "$ACCESS_POINT" ]; then
        echo "Ingress Access Point: $ACCESS_POINT"
        echo ""
        echo "Test URLs (add to /etc/hosts for local testing):"
        echo "$ACCESS_POINT $TEST_HOST"
        echo "$ACCESS_POINT $API_HOST"
        echo ""
        echo "Example curl commands:"
        echo "curl -H 'Host: $TEST_HOST' http://$ACCESS_POINT/"
        echo "curl -H 'Host: $API_HOST' http://$ACCESS_POINT/v1"
        echo "curl -k -H 'Host: $TEST_HOST' https://$ACCESS_POINT/"
    else
        echo "Access point not available"
    fi

    print_newline_with_separator

    echo ""
    echo "=== Useful Commands ==="
    echo "View Ingress: kubectl describe ingress $INGRESS_NAME -n $NAMESPACE"
    echo "Check TLS: kubectl describe secret demo-tls -n $NAMESPACE"
    echo "Controller logs: kubectl logs -n ingress-nginx deployment/ingress-nginx-controller"
    echo "Test routing: curl -H 'Host: example.com' http://ingress-ip/"
    echo "Delete Ingress: kubectl delete ingress $INGRESS_NAME $NODEPORT_INGRESS_NAME -n $NAMESPACE"

    print_newline_with_separator
}

# Cleanup function for script interruption
cleanup() {
    echo ""
    print_warning "Script interrupted. Current status:"
    kubectl get ingress -n $NAMESPACE 2>/dev/null || echo "No ingresses found"
    kubectl get secrets -n $NAMESPACE | grep tls 2>/dev/null || echo "No TLS secrets found"
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    exit 1
}

# Trap Ctrl+C
trap cleanup INT

# Main execution
main() {
    echo "=================================="
    echo "  Ingress Creation & Test Script"
    echo "=================================="

    # Pre-flight checks
    check_kubectl

    # Check ingress controller
    check_ingress_controller

    # Cleanup any existing resources
    cleanup_existing

    # Ensure backend resources exist
    ensure_backend_resources

    # Create TLS secret for testing
    create_tls_secret

    # Deploy Ingresses
    deploy_ingresses

    # Verify ingresses
    verify_ingresses

    # Get ingress access point
    get_ingress_ip

    # Test ingress routing
    test_ingress_routing

    # Test HTTPS
    test_https

    # Demonstrate path routing
    demonstrate_path_routing

    # Show final status
    show_final_status

    print_success "Script completed successfully!"

    echo ""
    echo "Ingress resources are now configured and ready for use."
    echo "Note: For production use, configure proper DNS and certificates."
}

# Run main function
main "$@"
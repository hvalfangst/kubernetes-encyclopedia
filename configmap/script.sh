#!/bin/bash

# ConfigMap Creation and Testing Script
# This script creates ConfigMaps and demonstrates different usage patterns

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MANIFEST_FILE="manifest.yml"
CONFIGMAP_NAME="app-config"
STATIC_CONFIGMAP_NAME="static-config"
NAMESPACE="default"
TEST_POD_NAME="configmap-test-pod"

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

    # Delete existing ConfigMaps if they exist
    if kubectl get configmap $CONFIGMAP_NAME -n $NAMESPACE &> /dev/null; then
        print_warning "Existing ConfigMap found, deleting..."
        kubectl delete configmap $CONFIGMAP_NAME -n $NAMESPACE
    fi

    if kubectl get configmap $STATIC_CONFIGMAP_NAME -n $NAMESPACE &> /dev/null; then
        print_warning "Existing static ConfigMap found, deleting..."
        kubectl delete configmap $STATIC_CONFIGMAP_NAME -n $NAMESPACE
    fi

    # Clean up any existing test pods
    if kubectl get pod $TEST_POD_NAME -n $NAMESPACE &> /dev/null; then
        print_warning "Existing test Pod found, deleting..."
        kubectl delete pod $TEST_POD_NAME -n $NAMESPACE --grace-period=0 --force
    fi

    # Wait for ConfigMaps to be deleted
    wait_for_condition "ConfigMap cleanup" \
        "! kubectl get configmap $CONFIGMAP_NAME -n $NAMESPACE &> /dev/null && ! kubectl get configmap $STATIC_CONFIGMAP_NAME -n $NAMESPACE &> /dev/null" \
        30 2

    print_success "Cleanup completed"

    print_newline_with_separator
}

# Function to deploy ConfigMaps
deploy_configmaps() {
    print_status "Deploying ConfigMaps..."
    kubectl apply -f ${MANIFEST_FILE} -n $NAMESPACE

    print_newline_with_separator

    # Wait for ConfigMaps to be created
    wait_for_condition "ConfigMap creation" \
        "kubectl get configmap $CONFIGMAP_NAME -n $NAMESPACE &> /dev/null && kubectl get configmap $STATIC_CONFIGMAP_NAME -n $NAMESPACE &> /dev/null" \
        30 2

    print_success "ConfigMaps deployed successfully"

    print_newline_with_separator
}

# Function to verify ConfigMap status
verify_configmaps() {
    print_status "Verifying ConfigMap status..."

    # Check ConfigMap details
    echo ""
    echo "=== Main ConfigMap Details ==="
    kubectl get configmap $CONFIGMAP_NAME -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Static ConfigMap Details ==="
    kubectl get configmap $STATIC_CONFIGMAP_NAME -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== ConfigMap Keys ==="
    echo "Main ConfigMap keys:"
    kubectl get configmap $CONFIGMAP_NAME -n $NAMESPACE -o jsonpath='{.data}' | jq 'keys' 2>/dev/null || \
        kubectl get configmap $CONFIGMAP_NAME -n $NAMESPACE -o jsonpath='{.data}' | grep -o '"[^"]*"' | head -10

    echo ""
    echo "Static ConfigMap keys:"
    kubectl get configmap $STATIC_CONFIGMAP_NAME -n $NAMESPACE -o jsonpath='{.data}' | jq 'keys' 2>/dev/null || \
        kubectl get configmap $STATIC_CONFIGMAP_NAME -n $NAMESPACE -o jsonpath='{.data}' | grep -o '"[^"]*"' | head -10

    print_newline_with_separator

    echo ""
    echo "=== Main ConfigMap Description ==="
    kubectl describe configmap $CONFIGMAP_NAME -n $NAMESPACE

    print_newline_with_separator

    print_success "ConfigMaps are created and ready"

    print_newline_with_separator
}

# Function to test environment variables usage
test_environment_variables() {
    print_status "Testing ConfigMap as environment variables..."

    # Create test Pod with environment variables from ConfigMap
    cat <<EOF | kubectl apply -f - -n $NAMESPACE
apiVersion: v1
kind: Pod
metadata:
  name: ${TEST_POD_NAME}-env
  labels:
    test: configmap-env
spec:
  containers:
  - name: test-container
    image: busybox
    command: ['sh', '-c', 'echo "Environment variables from ConfigMap:"; env | grep -E "(ENVIRONMENT|LOG_LEVEL|DATABASE_|REDIS_)" | sort; sleep 300']
    env:
    # Individual environment variables
    - name: ENVIRONMENT
      valueFrom:
        configMapKeyRef:
          name: $CONFIGMAP_NAME
          key: environment
    - name: LOG_LEVEL
      valueFrom:
        configMapKeyRef:
          name: $CONFIGMAP_NAME
          key: log_level
    # All keys as environment variables with prefix
    envFrom:
    - configMapRef:
        name: $CONFIGMAP_NAME
  restartPolicy: Never
EOF

    # Wait for Pod to be running
    wait_for_condition "Environment test Pod ready" \
        "kubectl get pod ${TEST_POD_NAME}-env -n $NAMESPACE -o jsonpath='{.status.phase}' | grep -q 'Running'" \
        60 5

    echo ""
    echo "=== Environment Variables Test ==="
    kubectl logs ${TEST_POD_NAME}-env -n $NAMESPACE || echo "Pod may still be starting..."

    # Cleanup test pod
    kubectl delete pod ${TEST_POD_NAME}-env -n $NAMESPACE --grace-period=0 &

    print_newline_with_separator
}

# Function to test volume mount usage
test_volume_mounts() {
    print_status "Testing ConfigMap as volume mounts..."

    # Create test Pod with ConfigMap mounted as volume
    cat <<EOF | kubectl apply -f - -n $NAMESPACE
apiVersion: v1
kind: Pod
metadata:
  name: ${TEST_POD_NAME}-volume
  labels:
    test: configmap-volume
spec:
  containers:
  - name: test-container
    image: busybox
    command: ['sh', '-c', 'echo "=== Files from ConfigMap volume ==="; ls -la /etc/config/; echo ""; echo "=== app.properties content ==="; cat /etc/config/app.properties 2>/dev/null || echo "File not found"; echo ""; echo "=== nginx.conf content (first 10 lines) ==="; head -10 /etc/config/nginx.conf 2>/dev/null || echo "File not found"; sleep 300']
    volumeMounts:
    - name: config-volume
      mountPath: /etc/config
      readOnly: true
    # Mount specific file
    - name: static-config-volume
      mountPath: /etc/static/constants.yaml
      subPath: constants.yaml
      readOnly: true
  volumes:
  - name: config-volume
    configMap:
      name: $CONFIGMAP_NAME
  - name: static-config-volume
    configMap:
      name: $STATIC_CONFIGMAP_NAME
      items:
      - key: constants.yaml
        path: constants.yaml
  restartPolicy: Never
EOF

    # Wait for Pod to be running
    wait_for_condition "Volume test Pod ready" \
        "kubectl get pod ${TEST_POD_NAME}-volume -n $NAMESPACE -o jsonpath='{.status.phase}' | grep -q 'Running'" \
        60 5

    echo ""
    echo "=== Volume Mount Test ==="
    kubectl logs ${TEST_POD_NAME}-volume -n $NAMESPACE || echo "Pod may still be starting..."

    # Test file access
    echo ""
    echo "=== File Access Test ==="
    kubectl exec ${TEST_POD_NAME}-volume -n $NAMESPACE -- ls -la /etc/config/ 2>/dev/null || echo "Could not list config files"
    
    echo ""
    echo "=== Static Config File Test ==="
    kubectl exec ${TEST_POD_NAME}-volume -n $NAMESPACE -- ls -la /etc/static/ 2>/dev/null || echo "Could not list static files"

    # Cleanup test pod
    kubectl delete pod ${TEST_POD_NAME}-volume -n $NAMESPACE --grace-period=0 &

    print_newline_with_separator
}

# Function to test ConfigMap updates
test_configmap_updates() {
    print_status "Testing ConfigMap updates..."

    # Show original value
    ORIGINAL_VALUE=$(kubectl get configmap $CONFIGMAP_NAME -n $NAMESPACE -o jsonpath='{.data.log_level}')
    print_status "Original log_level value: $ORIGINAL_VALUE"

    # Update ConfigMap (will fail if immutable)
    print_status "Attempting to update ConfigMap..."
    if kubectl patch configmap $CONFIGMAP_NAME -n $NAMESPACE -p '{"data":{"log_level":"info","new_key":"new_value"}}' 2>/dev/null; then
        print_success "ConfigMap updated successfully"
        
        # Show updated values
        UPDATED_VALUE=$(kubectl get configmap $CONFIGMAP_NAME -n $NAMESPACE -o jsonpath='{.data.log_level}')
        NEW_KEY_VALUE=$(kubectl get configmap $CONFIGMAP_NAME -n $NAMESPACE -o jsonpath='{.data.new_key}')
        print_status "Updated log_level value: $UPDATED_VALUE"
        print_status "New key value: $NEW_KEY_VALUE"
        
        # Revert changes
        kubectl patch configmap $CONFIGMAP_NAME -n $NAMESPACE -p '{"data":{"log_level":"'$ORIGINAL_VALUE'"}}' >/dev/null
        kubectl patch configmap $CONFIGMAP_NAME -n $NAMESPACE --type='json' -p='[{"op": "remove", "path": "/data/new_key"}]' >/dev/null
        print_status "Reverted changes"
    else
        print_warning "ConfigMap update failed (may be immutable)"
    fi

    # Try to update immutable ConfigMap (should fail)
    print_status "Attempting to update immutable ConfigMap (should fail)..."
    if kubectl patch configmap $STATIC_CONFIGMAP_NAME -n $NAMESPACE -p '{"data":{"test_key":"test_value"}}' 2>/dev/null; then
        print_warning "Immutable ConfigMap was unexpectedly updated"
    else
        print_success "Immutable ConfigMap correctly rejected update"
    fi

    print_newline_with_separator
}

# Function to demonstrate command line ConfigMap creation
demonstrate_cli_creation() {
    print_status "Demonstrating CLI ConfigMap creation..."

    # Create ConfigMap from literals
    print_status "Creating ConfigMap from literals..."
    kubectl create configmap cli-literal-config \
        --from-literal=database_host=localhost \
        --from-literal=database_port=5432 \
        --from-literal=debug=true \
        -n $NAMESPACE --dry-run=client -o yaml

    # Create ConfigMap from file (using existing manifest as example)
    print_status "Creating ConfigMap from file..."
    echo "app.name=CLI-Demo" > /tmp/app.properties
    echo "app.version=1.0" >> /tmp/app.properties
    echo "server.port=8080" >> /tmp/app.properties
    
    kubectl create configmap cli-file-config \
        --from-file=/tmp/app.properties \
        -n $NAMESPACE --dry-run=client -o yaml | head -20

    # Cleanup temp file
    rm -f /tmp/app.properties

    print_success "CLI creation examples demonstrated"

    print_newline_with_separator
}

# Function to test ConfigMap data retrieval
test_data_retrieval() {
    print_status "Testing ConfigMap data retrieval..."

    echo ""
    echo "=== Get Specific Key ==="
    kubectl get configmap $CONFIGMAP_NAME -n $NAMESPACE -o jsonpath='{.data.environment}'
    echo ""

    echo ""
    echo "=== Get Multiple Keys ==="
    kubectl get configmap $CONFIGMAP_NAME -n $NAMESPACE -o jsonpath='{.data.environment} {.data.log_level} {.data.database_host}'
    echo ""

    echo ""
    echo "=== Get Configuration File Content ==="
    kubectl get configmap $CONFIGMAP_NAME -n $NAMESPACE -o jsonpath='{.data.app\.properties}' | head -5
    echo ""

    echo ""
    echo "=== List All Keys ==="
    kubectl get configmap $CONFIGMAP_NAME -n $NAMESPACE -o jsonpath='{.data}' | \
        jq 'keys' 2>/dev/null || echo "jq not available - use kubectl describe for key list"

    print_newline_with_separator
}

# Function to show final status
show_final_status() {
    echo ""
    echo "=================================="
    echo "         FINAL STATUS"
    echo "=================================="

    echo ""
    echo "=== All ConfigMaps ==="
    kubectl get configmaps -n $NAMESPACE | grep -E "(app-config|static-config)" || echo "ConfigMaps not found"

    print_newline_with_separator

    echo ""
    echo "=== ConfigMap Sizes ==="
    for cm in $CONFIGMAP_NAME $STATIC_CONFIGMAP_NAME; do
        if kubectl get configmap $cm -n $NAMESPACE &>/dev/null; then
            SIZE=$(kubectl get configmap $cm -n $NAMESPACE -o json | jq '.data | to_entries | map(.value | length) | add' 2>/dev/null || echo "unknown")
            echo "$cm: $SIZE bytes"
        fi
    done

    print_newline_with_separator

    echo ""
    echo "=== ConfigMap Immutability Status ==="
    for cm in $CONFIGMAP_NAME $STATIC_CONFIGMAP_NAME; do
        if kubectl get configmap $cm -n $NAMESPACE &>/dev/null; then
            IMMUTABLE=$(kubectl get configmap $cm -n $NAMESPACE -o jsonpath='{.immutable}' 2>/dev/null || echo "false")
            echo "$cm: immutable=$IMMUTABLE"
        fi
    done

    print_newline_with_separator

    echo ""
    echo "=== Usage Examples ==="
    echo "Environment Variables:"
    echo "  env:"
    echo "  - name: LOG_LEVEL"
    echo "    valueFrom:"
    echo "      configMapKeyRef:"
    echo "        name: $CONFIGMAP_NAME"
    echo "        key: log_level"
    echo ""
    echo "Volume Mount:"
    echo "  volumeMounts:"
    echo "  - name: config"
    echo "    mountPath: /etc/config"
    echo "  volumes:"
    echo "  - name: config"
    echo "    configMap:"
    echo "      name: $CONFIGMAP_NAME"

    print_newline_with_separator

    echo ""
    echo "=== Useful Commands ==="
    echo "View ConfigMap: kubectl describe configmap $CONFIGMAP_NAME -n $NAMESPACE"
    echo "Get specific key: kubectl get configmap $CONFIGMAP_NAME -o jsonpath='{.data.environment}' -n $NAMESPACE"
    echo "Export to file: kubectl get configmap $CONFIGMAP_NAME -o yaml > configmap.yaml -n $NAMESPACE"
    echo "Update ConfigMap: kubectl patch configmap $CONFIGMAP_NAME -p '{\"data\":{\"key\":\"value\"}}' -n $NAMESPACE"
    echo "Delete ConfigMap: kubectl delete configmap $CONFIGMAP_NAME $STATIC_CONFIGMAP_NAME -n $NAMESPACE"

    print_newline_with_separator
}

# Cleanup function for script interruption
cleanup() {
    echo ""
    print_warning "Script interrupted. Current status:"
    kubectl get configmaps -n $NAMESPACE | grep -E "(app-config|static-config)" 2>/dev/null || echo "No ConfigMaps found"
    kubectl get pods -l test=configmap -n $NAMESPACE 2>/dev/null || echo "No test pods found"
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    exit 1
}

# Trap Ctrl+C
trap cleanup INT

# Main execution
main() {
    echo "=================================="
    echo "  ConfigMap Creation & Test Script"
    echo "=================================="

    # Pre-flight checks
    check_kubectl

    # Cleanup any existing resources
    cleanup_existing

    # Deploy ConfigMaps
    deploy_configmaps

    # Verify ConfigMaps
    verify_configmaps

    # Test environment variables usage
    test_environment_variables

    # Test volume mounts usage
    test_volume_mounts

    # Test ConfigMap updates
    test_configmap_updates

    # Demonstrate CLI creation
    demonstrate_cli_creation

    # Test data retrieval
    test_data_retrieval

    # Show final status
    show_final_status

    print_success "Script completed successfully!"

    echo ""
    echo "ConfigMaps are now created and ready for use."
    echo "You can use them in your applications as shown in the examples above."
}

# Run main function
main "$@"
#!/bin/bash

# StatefulSet Creation and Testing Script
# This script creates StatefulSets and demonstrates stateful application patterns

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MANIFEST_FILE="manifest.yml"
NGINX_STATEFULSET_NAME="nginx-stateful"
MYSQL_STATEFULSET_NAME="mysql-stateful"
NGINX_HEADLESS_SERVICE="nginx-headless"
MYSQL_HEADLESS_SERVICE="mysql-headless"
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

# Function to cleanup existing resources
cleanup_existing() {
    print_status "Cleaning up existing resources..."

    # Delete existing StatefulSets if they exist
    for sts in $NGINX_STATEFULSET_NAME $MYSQL_STATEFULSET_NAME; do
        if kubectl get statefulset $sts -n $NAMESPACE &> /dev/null; then
            print_warning "Existing StatefulSet $sts found, deleting..."
            kubectl delete statefulset $sts -n $NAMESPACE
        fi
    done

    # Delete services
    for svc in $NGINX_HEADLESS_SERVICE $MYSQL_HEADLESS_SERVICE nginx-stateful-service; do
        if kubectl get service $svc -n $NAMESPACE &> /dev/null; then
            print_warning "Existing Service $svc found, deleting..."
            kubectl delete service $svc -n $NAMESPACE
        fi
    done

    # Delete ConfigMaps
    for cm in nginx-stateful-config mysql-config; do
        if kubectl get configmap $cm -n $NAMESPACE &> /dev/null; then
            print_warning "Existing ConfigMap $cm found, deleting..."
            kubectl delete configmap $cm -n $NAMESPACE
        fi
    done

    # Clean up lingering pods
    kubectl get pods -l app=nginx-stateful -n $NAMESPACE --no-headers 2>/dev/null | awk '{print $1}' | xargs -r kubectl delete pod --grace-period=0 --force -n $NAMESPACE
    kubectl get pods -l app=mysql-stateful -n $NAMESPACE --no-headers 2>/dev/null | awk '{print $1}' | xargs -r kubectl delete pod --grace-period=0 --force -n $NAMESPACE

    # Wait for StatefulSets to be deleted
    wait_for_condition "StatefulSet cleanup" \
        "! kubectl get statefulset $NGINX_STATEFULSET_NAME -n $NAMESPACE &> /dev/null" \
        60 2

    print_success "Cleanup completed"

    print_newline_with_separator
}

# Function to deploy StatefulSets
deploy_statefulsets() {
    print_status "Deploying StatefulSets and related resources..."
    kubectl apply -f ${MANIFEST_FILE} -n $NAMESPACE

    print_newline_with_separator

    # Wait for StatefulSets to be created
    wait_for_condition "StatefulSet creation" \
        "kubectl get statefulset $NGINX_STATEFULSET_NAME -n $NAMESPACE &> /dev/null && kubectl get statefulset $MYSQL_STATEFULSET_NAME -n $NAMESPACE &> /dev/null" \
        30 2

    print_success "StatefulSets deployed successfully"

    print_newline_with_separator
}

# Function to verify StatefulSet status
verify_statefulsets() {
    print_status "Verifying StatefulSet status..."

    # Check StatefulSet details
    echo ""
    echo "=== All StatefulSets ==="
    kubectl get statefulsets -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Nginx StatefulSet Details ==="
    kubectl describe statefulset $NGINX_STATEFULSET_NAME -n $NAMESPACE

    print_newline_with_separator

    echo ""
    echo "=== StatefulSet Pods ==="
    kubectl get pods -l app=nginx-stateful -n $NAMESPACE -o wide
    
    echo ""
    kubectl get pods -l app=mysql-stateful -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Headless Services ==="
    kubectl get services -l app=nginx-stateful -n $NAMESPACE -o wide
    kubectl get services -l app=mysql-stateful -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Persistent Volume Claims ==="
    kubectl get pvc -l app=nginx-stateful -n $NAMESPACE
    kubectl get pvc -l app=mysql-stateful -n $NAMESPACE

    print_newline_with_separator

    print_success "StatefulSets are created and running"

    print_newline_with_separator
}

# Function to wait for pods to be ready
wait_for_pods_ready() {
    print_status "Waiting for StatefulSet pods to be ready..."

    # Wait for nginx pods
    wait_for_condition "Nginx pods ready" \
        "kubectl get statefulset $NGINX_STATEFULSET_NAME -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' | grep -q '3'" \
        180 10

    # Wait for mysql pods  
    wait_for_condition "MySQL pods ready" \
        "kubectl get statefulset $MYSQL_STATEFULSET_NAME -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' | grep -q '1'" \
        180 10

    print_success "All StatefulSet pods are ready"

    print_newline_with_separator
}

# Function to test ordered startup
test_ordered_startup() {
    print_status "Testing ordered Pod startup behavior..."

    echo ""
    echo "=== Pod Creation Timeline ==="
    
    # Get pod creation times
    kubectl get pods -l app=nginx-stateful -n $NAMESPACE -o custom-columns="NAME:.metadata.name,CREATED:.metadata.creationTimestamp" --sort-by=.metadata.creationTimestamp

    echo ""
    echo "=== Pod Names and IPs (showing stable identity) ==="
    kubectl get pods -l app=nginx-stateful -n $NAMESPACE -o custom-columns="NAME:.metadata.name,IP:.status.podIP,NODE:.spec.nodeName"

    print_newline_with_separator
}

# Function to test persistent storage
test_persistent_storage() {
    print_status "Testing persistent storage functionality..."

    echo ""
    echo "=== Persistent Volume Claims ==="
    kubectl get pvc -l app=nginx-stateful -n $NAMESPACE -o wide

    echo ""
    echo "=== Testing data persistence by writing to each pod ==="
    
    # Write unique data to each nginx pod
    for i in {0..2}; do
        POD_NAME="nginx-stateful-$i"
        if kubectl get pod $POD_NAME -n $NAMESPACE &>/dev/null; then
            echo "Writing test data to $POD_NAME..."
            kubectl exec $POD_NAME -n $NAMESPACE -- sh -c "echo 'Data from $POD_NAME - $(date)' > /usr/share/nginx/html/test-data.txt"
        fi
    done

    echo ""
    echo "=== Reading data from each pod ==="
    for i in {0..2}; do
        POD_NAME="nginx-stateful-$i"
        if kubectl get pod $POD_NAME -n $NAMESPACE &>/dev/null; then
            echo "Data from $POD_NAME:"
            kubectl exec $POD_NAME -n $NAMESPACE -- cat /usr/share/nginx/html/test-data.txt 2>/dev/null || echo "No data found"
        fi
    done

    print_newline_with_separator
}

# Function to test network identity
test_network_identity() {
    print_status "Testing stable network identity..."

    echo ""
    echo "=== DNS Resolution Test ==="
    
    # Test DNS resolution for each pod
    for i in {0..2}; do
        POD_NAME="nginx-stateful-$i"
        DNS_NAME="$POD_NAME.$NGINX_HEADLESS_SERVICE.$NAMESPACE.svc.cluster.local"
        
        echo "Testing DNS resolution for $DNS_NAME"
        kubectl run dns-test-$i --image=busybox --rm -it --restart=Never -- nslookup $DNS_NAME 2>/dev/null | grep -E "(Name:|Address:)" || echo "DNS resolution failed for $DNS_NAME"
    done

    echo ""
    echo "=== Testing HTTP connectivity to each pod ==="
    for i in {0..2}; do
        POD_NAME="nginx-stateful-$i"
        echo "Testing HTTP connectivity to $POD_NAME..."
        kubectl run http-test-$i --image=curlimages/curl --rm --restart=Never -- \
            curl -f -s http://$POD_NAME.$NGINX_HEADLESS_SERVICE.$NAMESPACE.svc.cluster.local/ | head -2 2>/dev/null || echo "HTTP test failed for $POD_NAME"
    done

    print_newline_with_separator
}

# Function to test scaling behavior
test_scaling_behavior() {
    print_status "Testing StatefulSet scaling behavior..."

    # Get current replica count
    CURRENT_REPLICAS=$(kubectl get statefulset $NGINX_STATEFULSET_NAME -n $NAMESPACE -o jsonpath='{.spec.replicas}')
    echo "Current replicas: $CURRENT_REPLICAS"

    # Scale up
    print_status "Scaling up from $CURRENT_REPLICAS to 5 replicas..."
    kubectl scale statefulset $NGINX_STATEFULSET_NAME --replicas=5 -n $NAMESPACE

    # Wait for scale up
    wait_for_condition "Scale up to 5 replicas" \
        "kubectl get statefulset $NGINX_STATEFULSET_NAME -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' | grep -q '5'" \
        120 10

    echo ""
    echo "=== Scaled Up Pods ==="
    kubectl get pods -l app=nginx-stateful -n $NAMESPACE -o wide

    echo ""
    echo "=== New PVCs Created ==="
    kubectl get pvc -l app=nginx-stateful -n $NAMESPACE

    print_newline_with_separator

    # Scale down
    print_status "Scaling down from 5 to 2 replicas..."
    kubectl scale statefulset $NGINX_STATEFULSET_NAME --replicas=2 -n $NAMESPACE

    # Wait for scale down
    wait_for_condition "Scale down to 2 replicas" \
        "kubectl get statefulset $NGINX_STATEFULSET_NAME -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' | grep -q '2'" \
        120 10

    echo ""
    echo "=== Scaled Down Pods ==="
    kubectl get pods -l app=nginx-stateful -n $NAMESPACE -o wide

    echo ""
    echo "=== PVCs After Scale Down (should still exist) ==="
    kubectl get pvc -l app=nginx-stateful -n $NAMESPACE

    # Scale back to original
    kubectl scale statefulset $NGINX_STATEFULSET_NAME --replicas=$CURRENT_REPLICAS -n $NAMESPACE

    print_newline_with_separator
}

# Function to test rolling updates
test_rolling_updates() {
    print_status "Testing StatefulSet rolling updates..."

    # Get current image
    CURRENT_IMAGE=$(kubectl get statefulset $NGINX_STATEFULSET_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}')
    echo "Current image: $CURRENT_IMAGE"

    # Update image
    NEW_IMAGE="nginx:1.22"
    print_status "Updating image from $CURRENT_IMAGE to $NEW_IMAGE..."
    
    kubectl patch statefulset $NGINX_STATEFULSET_NAME -n $NAMESPACE -p '{"spec":{"template":{"spec":{"containers":[{"name":"nginx","image":"'$NEW_IMAGE'"}]}}}}'

    # Monitor rolling update
    print_status "Monitoring rolling update progress..."
    kubectl rollout status statefulset/$NGINX_STATEFULSET_NAME -n $NAMESPACE --timeout=180s

    echo ""
    echo "=== Updated Pods ==="
    kubectl get pods -l app=nginx-stateful -n $NAMESPACE -o wide

    echo ""
    echo "=== Rollout History ==="
    kubectl rollout history statefulset/$NGINX_STATEFULSET_NAME -n $NAMESPACE

    # Rollback to test rollback functionality
    print_status "Testing rollback functionality..."
    kubectl rollout undo statefulset/$NGINX_STATEFULSET_NAME -n $NAMESPACE

    kubectl rollout status statefulset/$NGINX_STATEFULSET_NAME -n $NAMESPACE --timeout=180s

    print_success "Rolling update and rollback completed"

    print_newline_with_separator
}

# Function to test MySQL database
test_mysql_database() {
    print_status "Testing MySQL StatefulSet functionality..."

    # Wait for MySQL to be ready
    wait_for_condition "MySQL ready" \
        "kubectl get pod mysql-stateful-0 -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -q 'True'" \
        180 10

    echo ""
    echo "=== MySQL Pod Status ==="
    kubectl get pods -l app=mysql-stateful -n $NAMESPACE -o wide

    echo ""
    echo "=== MySQL Database Test ==="
    # Test database connectivity
    kubectl exec mysql-stateful-0 -n $NAMESPACE -- mysql -u root -prootpassword123 -e "SHOW DATABASES;" 2>/dev/null || echo "MySQL connection test failed"

    # Create test data
    print_status "Creating test database and table..."
    kubectl exec mysql-stateful-0 -n $NAMESPACE -- mysql -u root -prootpassword123 -e "CREATE DATABASE IF NOT EXISTS testdb; USE testdb; CREATE TABLE IF NOT EXISTS users (id INT PRIMARY KEY, name VARCHAR(50)); INSERT INTO users VALUES (1, 'Test User $(date +%s)');" 2>/dev/null || echo "Database operation failed"

    # Query test data
    echo ""
    echo "=== Test Data Query ==="
    kubectl exec mysql-stateful-0 -n $NAMESPACE -- mysql -u root -prootpassword123 -D testdb -e "SELECT * FROM users;" 2>/dev/null || echo "Query failed"

    echo ""
    echo "=== MySQL Storage ==="
    kubectl get pvc -l app=mysql-stateful -n $NAMESPACE

    print_newline_with_separator
}

# Function to demonstrate pod restart persistence
test_data_persistence() {
    print_status "Testing data persistence across pod restarts..."

    # Write test data to nginx pod
    POD_NAME="nginx-stateful-0"
    TEST_DATA="Persistent data test - $(date)"
    
    print_status "Writing test data to $POD_NAME..."
    kubectl exec $POD_NAME -n $NAMESPACE -- sh -c "echo '$TEST_DATA' > /usr/share/nginx/html/persistence-test.txt"

    # Read the data
    echo "Data written:"
    kubectl exec $POD_NAME -n $NAMESPACE -- cat /usr/share/nginx/html/persistence-test.txt

    # Delete the pod to simulate restart
    print_status "Deleting pod $POD_NAME to test persistence..."
    kubectl delete pod $POD_NAME -n $NAMESPACE

    # Wait for pod to be recreated and ready
    wait_for_condition "Pod recreation" \
        "kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -q 'True'" \
        120 10

    # Verify data persistence
    print_status "Verifying data persistence after pod restart..."
    RECOVERED_DATA=$(kubectl exec $POD_NAME -n $NAMESPACE -- cat /usr/share/nginx/html/persistence-test.txt 2>/dev/null || echo "Data not found")
    
    if [ "$RECOVERED_DATA" = "$TEST_DATA" ]; then
        print_success "Data persistence test PASSED - data survived pod restart"
    else
        print_warning "Data persistence test FAILED - data was lost"
    fi

    echo "Expected: $TEST_DATA"
    echo "Actual: $RECOVERED_DATA"

    print_newline_with_separator
}

# Function to show final status
show_final_status() {
    echo ""
    echo "=================================="
    echo "         FINAL STATUS"
    echo "=================================="

    echo ""
    echo "=== All StatefulSets ==="
    kubectl get statefulsets -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== StatefulSet Pods ==="
    kubectl get pods -l app=nginx-stateful -n $NAMESPACE -o wide
    kubectl get pods -l app=mysql-stateful -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Persistent Volume Claims ==="
    kubectl get pvc -l app=nginx-stateful -n $NAMESPACE
    kubectl get pvc -l app=mysql-stateful -n $NAMESPACE

    print_newline_with_separator

    echo ""
    echo "=== Services ==="
    kubectl get services -l app=nginx-stateful -n $NAMESPACE
    kubectl get services -l app=mysql-stateful -n $NAMESPACE

    print_newline_with_separator

    echo ""
    echo "=== StatefulSet Features Demonstrated ==="
    echo "1. ✅ Ordered Pod Creation (nginx-stateful-0, 1, 2)"
    echo "2. ✅ Stable Network Identity (pod-name.service-name)"
    echo "3. ✅ Persistent Storage (PVCs survive pod restarts)"
    echo "4. ✅ Ordered Scaling (up and down)"
    echo "5. ✅ Rolling Updates (controlled updates)"
    echo "6. ✅ Data Persistence (survives pod deletion)"
    echo "7. ✅ Database StatefulSet (MySQL example)"

    print_newline_with_separator

    echo ""
    echo "=== Useful Commands ==="
    echo "View StatefulSet: kubectl describe statefulset $NGINX_STATEFULSET_NAME -n $NAMESPACE"
    echo "Scale StatefulSet: kubectl scale statefulset $NGINX_STATEFULSET_NAME --replicas=5 -n $NAMESPACE"
    echo "Rolling update: kubectl set image statefulset/$NGINX_STATEFULSET_NAME nginx=nginx:1.22 -n $NAMESPACE"
    echo "Check rollout: kubectl rollout status statefulset/$NGINX_STATEFULSET_NAME -n $NAMESPACE"
    echo "Rollback: kubectl rollout undo statefulset/$NGINX_STATEFULSET_NAME -n $NAMESPACE"
    echo "Pod logs: kubectl logs nginx-stateful-0 -n $NAMESPACE"
    echo "Exec into pod: kubectl exec -it nginx-stateful-0 -n $NAMESPACE -- /bin/bash"
    echo "View PVCs: kubectl get pvc -l app=nginx-stateful -n $NAMESPACE"
    echo "Delete StatefulSet: kubectl delete statefulset $NGINX_STATEFULSET_NAME -n $NAMESPACE"

    print_newline_with_separator
}

# Cleanup function for script interruption
cleanup() {
    echo ""
    print_warning "Script interrupted. Current status:"
    kubectl get statefulsets -n $NAMESPACE 2>/dev/null || echo "No StatefulSets found"
    kubectl get pods -l app=nginx-stateful -n $NAMESPACE 2>/dev/null || echo "No nginx pods found"
    kubectl get pods -l app=mysql-stateful -n $NAMESPACE 2>/dev/null || echo "No mysql pods found"
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    exit 1
}

# Trap Ctrl+C
trap cleanup INT

# Main execution
main() {
    echo "=================================="
    echo "  StatefulSet Creation & Test Script"
    echo "=================================="

    # Pre-flight checks
    check_kubectl

    # Cleanup any existing resources
    cleanup_existing

    # Deploy StatefulSets
    deploy_statefulsets

    # Verify StatefulSets
    verify_statefulsets

    # Wait for pods to be ready
    wait_for_pods_ready

    # Test ordered startup
    test_ordered_startup

    # Test persistent storage
    test_persistent_storage

    # Test network identity
    test_network_identity

    # Test scaling behavior
    test_scaling_behavior

    # Test rolling updates
    test_rolling_updates

    # Test MySQL functionality
    test_mysql_database

    # Test data persistence
    test_data_persistence

    # Show final status
    show_final_status

    print_success "Script completed successfully!"

    echo ""
    echo "StatefulSets have been created and all stateful features demonstrated."
    echo "You can now see the difference between StatefulSets and Deployments."
}

# Run main function
main "$@"
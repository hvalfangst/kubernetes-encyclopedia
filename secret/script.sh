#!/bin/bash

# Secret Creation and Testing Script
# This script creates Secrets and demonstrates different usage patterns and security considerations

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MANIFEST_FILE="manifest.yml"
SECRET_NAME="app-secrets"
TLS_SECRET_NAME="demo-tls-secret"
DOCKER_SECRET_NAME="docker-registry-secret"
BASIC_AUTH_SECRET_NAME="basic-auth-secret"
SSH_SECRET_NAME="git-ssh-secret"
NAMESPACE="default"
TEST_POD_NAME="secret-test-pod"

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

    # List of secrets to clean up
    SECRETS=($SECRET_NAME $TLS_SECRET_NAME $DOCKER_SECRET_NAME $BASIC_AUTH_SECRET_NAME $SSH_SECRET_NAME)

    # Delete existing Secrets if they exist
    for secret in "${SECRETS[@]}"; do
        if kubectl get secret $secret -n $NAMESPACE &> /dev/null; then
            print_warning "Existing Secret $secret found, deleting..."
            kubectl delete secret $secret -n $NAMESPACE
        fi
    done

    # Clean up any existing test pods
    kubectl get pods -l test=secret -n $NAMESPACE --no-headers 2>/dev/null | awk '{print $1}' | xargs -r kubectl delete pod --grace-period=0 --force -n $NAMESPACE

    # Wait for Secrets to be deleted
    wait_for_condition "Secret cleanup" \
        "! kubectl get secret $SECRET_NAME -n $NAMESPACE &> /dev/null" \
        30 2

    print_success "Cleanup completed"

    print_newline_with_separator
}

# Function to deploy Secrets
deploy_secrets() {
    print_status "Deploying Secrets..."
    kubectl apply -f ${MANIFEST_FILE} -n $NAMESPACE

    print_newline_with_separator

    # Wait for Secrets to be created
    wait_for_condition "Secret creation" \
        "kubectl get secret $SECRET_NAME -n $NAMESPACE &> /dev/null && kubectl get secret $TLS_SECRET_NAME -n $NAMESPACE &> /dev/null" \
        30 2

    print_success "Secrets deployed successfully"

    print_newline_with_separator
}

# Function to verify Secret status
verify_secrets() {
    print_status "Verifying Secret status..."

    # Check Secret details
    echo ""
    echo "=== All Secrets ==="
    kubectl get secrets -n $NAMESPACE | grep -E "(app-secrets|demo-tls|docker-registry|basic-auth|git-ssh)" || echo "No matching secrets found"

    print_newline_with_separator

    echo ""
    echo "=== Main Secret Details ==="
    kubectl describe secret $SECRET_NAME -n $NAMESPACE

    print_newline_with_separator

    echo ""
    echo "=== TLS Secret Details ==="
    kubectl describe secret $TLS_SECRET_NAME -n $NAMESPACE

    print_newline_with_separator

    echo ""
    echo "=== Secret Keys ==="
    echo "Main Secret keys:"
    kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data}' | jq 'keys' 2>/dev/null || \
        kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data}' | grep -o '"[^"]*"' | head -10

    echo ""
    echo "TLS Secret keys:"
    kubectl get secret $TLS_SECRET_NAME -n $NAMESPACE -o jsonpath='{.data}' | jq 'keys' 2>/dev/null || \
        kubectl get secret $TLS_SECRET_NAME -n $NAMESPACE -o jsonpath='{.data}' | grep -o '"[^"]*"'

    print_newline_with_separator

    print_success "Secrets are created and ready"

    print_newline_with_separator
}

# Function to test environment variables usage
test_environment_variables() {
    print_status "Testing Secret as environment variables..."

    # Create test Pod with environment variables from Secret
    cat <<EOF | kubectl apply -f - -n $NAMESPACE
apiVersion: v1
kind: Pod
metadata:
  name: ${TEST_POD_NAME}-env
  labels:
    test: secret-env
spec:
  containers:
  - name: test-container
    image: busybox
    command: ['sh', '-c', 'echo "Environment variables from Secret:"; env | grep -E "(DATABASE_|API_|JWT_)" | sort; echo "Full secret env vars:"; env | grep -v "KUBERNETES_" | grep -v "PATH" | sort; sleep 300']
    env:
    # Individual environment variables
    - name: DATABASE_PASSWORD
      valueFrom:
        secretKeyRef:
          name: $SECRET_NAME
          key: database_password
    - name: API_KEY
      valueFrom:
        secretKeyRef:
          name: $SECRET_NAME
          key: api_key
    # All keys as environment variables
    envFrom:
    - secretRef:
        name: $SECRET_NAME
  restartPolicy: Never
EOF

    # Wait for Pod to be running
    wait_for_condition "Environment test Pod ready" \
        "kubectl get pod ${TEST_POD_NAME}-env -n $NAMESPACE -o jsonpath='{.status.phase}' | grep -q 'Running'" \
        60 5

    echo ""
    echo "=== Environment Variables Test ==="
    kubectl logs ${TEST_POD_NAME}-env -n $NAMESPACE 2>/dev/null || echo "Pod may still be starting..."

    # Cleanup test pod
    kubectl delete pod ${TEST_POD_NAME}-env -n $NAMESPACE --grace-period=0 &

    print_newline_with_separator
}

# Function to test volume mount usage
test_volume_mounts() {
    print_status "Testing Secret as volume mounts..."

    # Create test Pod with Secret mounted as volume
    cat <<EOF | kubectl apply -f - -n $NAMESPACE
apiVersion: v1
kind: Pod
metadata:
  name: ${TEST_POD_NAME}-volume
  labels:
    test: secret-volume
spec:
  containers:
  - name: test-container
    image: busybox
    command: ['sh', '-c', 'echo "=== Files from Secret volume ==="; ls -la /etc/secrets/; echo ""; echo "=== Database config content ==="; cat /etc/secrets/database.conf 2>/dev/null | head -10 || echo "File not found"; echo ""; echo "=== File permissions ==="; ls -la /etc/secrets/ | head -5; echo ""; echo "=== TLS certificate info ==="; ls -la /etc/tls/ 2>/dev/null || echo "TLS volume not mounted"; sleep 300']
    volumeMounts:
    - name: secret-volume
      mountPath: /etc/secrets
      readOnly: true
    - name: tls-volume
      mountPath: /etc/tls
      readOnly: true
    # Mount specific file with custom permissions
    - name: ssh-key-volume
      mountPath: /etc/ssh-keys
      readOnly: true
      defaultMode: 0400
  volumes:
  - name: secret-volume
    secret:
      secretName: $SECRET_NAME
      defaultMode: 0400  # Read-only for owner only
  - name: tls-volume
    secret:
      secretName: $TLS_SECRET_NAME
      items:
      - key: tls.crt
        path: tls.crt
        mode: 0444
      - key: tls.key
        path: tls.key
        mode: 0400
  - name: ssh-key-volume
    secret:
      secretName: $SSH_SECRET_NAME
  restartPolicy: Never
EOF

    # Wait for Pod to be running
    wait_for_condition "Volume test Pod ready" \
        "kubectl get pod ${TEST_POD_NAME}-volume -n $NAMESPACE -o jsonpath='{.status.phase}' | grep -q 'Running'" \
        60 5

    echo ""
    echo "=== Volume Mount Test ==="
    kubectl logs ${TEST_POD_NAME}-volume -n $NAMESPACE 2>/dev/null || echo "Pod may still be starting..."

    # Test file access
    echo ""
    echo "=== File Access Test ==="
    kubectl exec ${TEST_POD_NAME}-volume -n $NAMESPACE -- ls -la /etc/secrets/ 2>/dev/null || echo "Could not list secret files"
    
    echo ""
    echo "=== Secret File Content Sample ==="
    kubectl exec ${TEST_POD_NAME}-volume -n $NAMESPACE -- head -3 /etc/secrets/database_username 2>/dev/null || echo "Could not read username file"

    # Cleanup test pod
    kubectl delete pod ${TEST_POD_NAME}-volume -n $NAMESPACE --grace-period=0 &

    print_newline_with_separator
}

# Function to test Docker registry secret
test_docker_registry_secret() {
    print_status "Testing Docker registry secret..."

    # Create test Pod with imagePullSecrets
    cat <<EOF | kubectl apply -f - -n $NAMESPACE
apiVersion: v1
kind: Pod
metadata:
  name: ${TEST_POD_NAME}-registry
  labels:
    test: secret-registry
spec:
  imagePullSecrets:
  - name: $DOCKER_SECRET_NAME
  containers:
  - name: test-container
    image: busybox  # Using public image for test
    command: ['sh', '-c', 'echo "Pod with imagePullSecret created successfully"; echo "Secret allows pulling from private registries"; sleep 120']
  restartPolicy: Never
EOF

    # Wait for Pod to be running or completed
    wait_for_condition "Registry test Pod ready" \
        "kubectl get pod ${TEST_POD_NAME}-registry -n $NAMESPACE -o jsonpath='{.status.phase}' | grep -E '(Running|Succeeded)'" \
        60 5

    echo ""
    echo "=== Docker Registry Secret Test ==="
    kubectl logs ${TEST_POD_NAME}-registry -n $NAMESPACE 2>/dev/null || echo "Pod may still be starting..."

    echo ""
    echo "=== Pod Events (checking for image pull issues) ==="
    kubectl describe pod ${TEST_POD_NAME}-registry -n $NAMESPACE | grep -A 10 Events | tail -10

    # Cleanup test pod
    kubectl delete pod ${TEST_POD_NAME}-registry -n $NAMESPACE --grace-period=0 &

    print_newline_with_separator
}

# Function to test secret data retrieval and decoding
test_secret_data_retrieval() {
    print_status "Testing Secret data retrieval and decoding..."

    echo ""
    echo "=== Base64 Encoded Data ==="
    kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.database_username}' && echo ""

    echo ""
    echo "=== Decoded Secret Values ==="
    echo "Database Username: $(kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.database_username}' | base64 -d)"
    echo "API Key (first 10 chars): $(kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.api_key}' | base64 -d | cut -c1-10)..."

    echo ""
    echo "=== All Secret Keys ==="
    kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data}' | \
        jq -r 'keys[]' 2>/dev/null || kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data}' | grep -o '"[^"]*"'

    echo ""
    echo "=== Secret Size Information ==="
    SECRET_SIZE=$(kubectl get secret $SECRET_NAME -n $NAMESPACE -o json | jq '.data | to_entries | map(.value | length) | add' 2>/dev/null || echo "unknown")
    echo "Total secret data size: $SECRET_SIZE bytes (base64 encoded)"

    print_newline_with_separator
}

# Function to demonstrate CLI secret creation
demonstrate_cli_creation() {
    print_status "Demonstrating CLI Secret creation..."

    # Create Secret from literals
    print_status "Creating Secret from literals (dry-run)..."
    kubectl create secret generic cli-literal-secret \
        --from-literal=username=admin \
        --from-literal=password=secretpass \
        --from-literal=api-key=abc123 \
        -n $NAMESPACE --dry-run=client -o yaml | head -20

    # Create TLS Secret (dry-run)
    print_status "Creating TLS Secret (dry-run)..."
    echo "This would create a TLS secret from cert files:"
    echo "kubectl create secret tls my-tls-secret --cert=tls.crt --key=tls.key"

    # Create Docker registry secret (dry-run)
    print_status "Creating Docker registry Secret (dry-run)..."
    echo "This would create a Docker registry secret:"
    echo "kubectl create secret docker-registry my-registry-secret \\"
    echo "  --docker-server=registry.example.com \\"
    echo "  --docker-username=user \\"
    echo "  --docker-password=pass \\"
    echo "  --docker-email=user@example.com"

    print_success "CLI creation examples demonstrated"

    print_newline_with_separator
}

# Function to test secret security
test_secret_security() {
    print_status "Testing Secret security considerations..."

    echo ""
    echo "=== RBAC Check ==="
    if kubectl auth can-i get secrets -n $NAMESPACE 2>/dev/null; then
        print_warning "Current user can access secrets"
    else
        print_success "Current user cannot access secrets (good for security)"
    fi

    echo ""
    echo "=== Secret Encryption Status ==="
    # Note: This is a simplified check - actual encryption verification requires cluster admin access
    if kubectl get secrets -n $NAMESPACE -o yaml | grep -q "k8s:enc:" 2>/dev/null; then
        print_success "Secrets appear to be encrypted at rest"
    else
        print_warning "Cannot verify encryption at rest status"
    fi

    echo ""
    echo "=== Secret Usage in Pods ==="
    PODS_USING_SECRETS=$(kubectl get pods -n $NAMESPACE -o yaml | grep -c "secretKeyRef\|secretRef" 2>/dev/null || echo "0")
    echo "Number of references to secrets in pods: $PODS_USING_SECRETS"

    echo ""
    echo "=== Secret Immutability Check ==="
    for secret in $SECRET_NAME $TLS_SECRET_NAME; do
        IMMUTABLE=$(kubectl get secret $secret -n $NAMESPACE -o jsonpath='{.immutable}' 2>/dev/null || echo "false")
        echo "$secret: immutable=$IMMUTABLE"
    done

    print_newline_with_separator
}

# Function to test secret updates
test_secret_updates() {
    print_status "Testing Secret updates..."

    # Show original value
    ORIGINAL_VALUE=$(kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.api_key}' | base64 -d)
    print_status "Original API key (first 10 chars): ${ORIGINAL_VALUE:0:10}..."

    # Update Secret
    print_status "Attempting to update Secret..."
    if kubectl patch secret $SECRET_NAME -n $NAMESPACE -p '{"stringData":{"api_key":"updated-api-key-value","new_secret":"new-secret-value"}}' 2>/dev/null; then
        print_success "Secret updated successfully"
        
        # Show updated values
        UPDATED_VALUE=$(kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.api_key}' | base64 -d)
        NEW_SECRET_VALUE=$(kubectl get secret $SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.new_secret}' | base64 -d)
        print_status "Updated API key: $UPDATED_VALUE"
        print_status "New secret value: $NEW_SECRET_VALUE"
        
        # Revert changes
        kubectl patch secret $SECRET_NAME -n $NAMESPACE -p '{"stringData":{"api_key":"'$ORIGINAL_VALUE'"}}' >/dev/null
        kubectl patch secret $SECRET_NAME -n $NAMESPACE --type='json' -p='[{"op": "remove", "path": "/data/new_secret"}]' >/dev/null 2>&1 || true
        print_status "Reverted changes"
    else
        print_warning "Secret update failed (may be immutable or RBAC restricted)"
    fi

    print_newline_with_separator
}

# Function to show final status
show_final_status() {
    echo ""
    echo "=================================="
    echo "         FINAL STATUS"
    echo "=================================="

    echo ""
    echo "=== All Secrets ==="
    kubectl get secrets -n $NAMESPACE | grep -E "(app-secrets|demo-tls|docker-registry|basic-auth|git-ssh|TYPE)" || echo "No matching secrets found"

    print_newline_with_separator

    echo ""
    echo "=== Secret Types ==="
    echo "Opaque secrets:"
    kubectl get secrets -n $NAMESPACE -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.type}{"\n"}{end}' | grep Opaque || echo "None"
    echo ""
    echo "TLS secrets:"
    kubectl get secrets -n $NAMESPACE -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.type}{"\n"}{end}' | grep kubernetes.io/tls || echo "None"

    print_newline_with_separator

    echo ""
    echo "=== Secret Sizes ==="
    for secret in $SECRET_NAME $TLS_SECRET_NAME $DOCKER_SECRET_NAME; do
        if kubectl get secret $secret -n $NAMESPACE &>/dev/null; then
            SIZE=$(kubectl get secret $secret -n $NAMESPACE -o json | jq '.data | to_entries | map(.value | length) | add' 2>/dev/null || echo "unknown")
            echo "$secret: $SIZE bytes (base64 encoded)"
        fi
    done

    print_newline_with_separator

    echo ""
    echo "=== Security Recommendations ==="
    echo "1. Enable encryption at rest for secrets"
    echo "2. Use RBAC to limit secret access"
    echo "3. Rotate secrets regularly"
    echo "4. Consider using external secret management"
    echo "5. Avoid storing secrets in container images"
    echo "6. Use immutable secrets for static data"

    print_newline_with_separator

    echo ""
    echo "=== Usage Examples ==="
    echo "Environment Variable:"
    echo "  env:"
    echo "  - name: DB_PASSWORD"
    echo "    valueFrom:"
    echo "      secretKeyRef:"
    echo "        name: $SECRET_NAME"
    echo "        key: database_password"
    echo ""
    echo "Volume Mount:"
    echo "  volumeMounts:"
    echo "  - name: secret-vol"
    echo "    mountPath: /etc/secrets"
    echo "  volumes:"
    echo "  - name: secret-vol"
    echo "    secret:"
    echo "      secretName: $SECRET_NAME"

    print_newline_with_separator

    echo ""
    echo "=== Useful Commands ==="
    echo "View Secret: kubectl describe secret $SECRET_NAME -n $NAMESPACE"
    echo "Decode value: kubectl get secret $SECRET_NAME -o jsonpath='{.data.key}' | base64 -d"
    echo "List keys: kubectl get secret $SECRET_NAME -o jsonpath='{.data}' | jq 'keys'"
    echo "Create from CLI: kubectl create secret generic mysecret --from-literal=key=value"
    echo "Update Secret: kubectl patch secret $SECRET_NAME -p '{\"stringData\":{\"key\":\"newvalue\"}}'"
    echo "Delete Secret: kubectl delete secret $SECRET_NAME -n $NAMESPACE"

    print_newline_with_separator
}

# Cleanup function for script interruption
cleanup() {
    echo ""
    print_warning "Script interrupted. Current status:"
    kubectl get secrets -n $NAMESPACE | grep -E "(app-secrets|demo-tls|docker-registry)" 2>/dev/null || echo "No secrets found"
    kubectl get pods -l test=secret -n $NAMESPACE 2>/dev/null || echo "No test pods found"
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    exit 1
}

# Trap Ctrl+C
trap cleanup INT

# Main execution
main() {
    echo "=================================="
    echo "  Secret Creation & Test Script"
    echo "=================================="

    # Pre-flight checks
    check_kubectl

    # Cleanup any existing resources
    cleanup_existing

    # Deploy Secrets
    deploy_secrets

    # Verify Secrets
    verify_secrets

    # Test environment variables usage
    test_environment_variables

    # Test volume mounts usage
    test_volume_mounts

    # Test Docker registry secret
    test_docker_registry_secret

    # Test secret data retrieval
    test_secret_data_retrieval

    # Demonstrate CLI creation
    demonstrate_cli_creation

    # Test secret security
    test_secret_security

    # Test secret updates
    test_secret_updates

    # Show final status
    show_final_status

    print_success "Script completed successfully!"

    echo ""
    echo "Secrets are now created and ready for use."
    echo "Remember to follow security best practices when using secrets in production."
}

# Run main function
main "$@"
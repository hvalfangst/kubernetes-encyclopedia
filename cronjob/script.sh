#!/bin/bash

# CronJob Deployment and Testing Script
# This script creates a CronJob, verifies it's running, manually triggers it, and follows logs

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MANIFEST_FILE="manifest.yml"
CRONJOB_NAME="echo-job"
NAMESPACE="default"
MANUAL_JOB_NAME="echo-manual-$(date +%s)"

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

    # Delete existing CronJob if it exists
    if kubectl get cronjob $CRONJOB_NAME -n $NAMESPACE &> /dev/null; then
        print_warning "Existing CronJob found, deleting..."
        kubectl delete cronjob $CRONJOB_NAME -n $NAMESPACE

        # Wait for CronJob to be deleted
        wait_for_condition "CronJob deletion" \
            "! kubectl get cronjob $CRONJOB_NAME -n $NAMESPACE &> /dev/null" \
            30 2
    fi

    # Delete any existing jobs from this CronJob
    if kubectl get jobs -l job-name=$CRONJOB_NAME -n $NAMESPACE --no-headers 2>/dev/null | grep -q .; then
        print_warning "Existing jobs found, deleting..."
        kubectl delete jobs -l job-name=$CRONJOB_NAME -n $NAMESPACE
    fi

    # Clean up any manual jobs
    if kubectl get jobs -l app=manual-backup -n $NAMESPACE --no-headers 2>/dev/null | grep -q .; then
        print_warning "Existing manual jobs found, deleting..."
        kubectl delete jobs -l app=manual-backup -n $NAMESPACE
    fi

    print_success "Cleanup completed"

    print_newline_with_separator
}

# Function to deploy CronJob
deploy_cronjob() {
    print_status "Deploying CronJob..."
    kubectl apply -f ${MANIFEST_FILE} -n $NAMESPACE

    print_newline_with_separator

    # Wait for CronJob to be created
    wait_for_condition "CronJob creation" \
        "kubectl get cronjob $CRONJOB_NAME -n $NAMESPACE &> /dev/null" \
        30 2

    print_success "CronJob deployed successfully"

    print_newline_with_separator
}

# Function to verify CronJob status
verify_cronjob() {
    print_status "Verifying CronJob status..."

    # Check CronJob details
    echo ""
    echo "=== CronJob Details ==="
    kubectl get cronjob $CRONJOB_NAME -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== CronJob Description ==="
    kubectl describe cronjob $CRONJOB_NAME -n $NAMESPACE

    print_newline_with_separator

    # Check if CronJob is suspended
    local suspended=$(kubectl get cronjob $CRONJOB_NAME -n $NAMESPACE -o jsonpath='{.spec.suspend}')
    if [ "$suspended" = "true" ]; then
        print_error "CronJob is suspended!"
        return 1
    fi

    print_success "CronJob is active and ready"

    print_newline_with_separator
}

# Function to manually trigger the job
trigger_manual_job() {
    print_status "Manually triggering job..."

    # Create a manual job from the CronJob
    kubectl create job "$MANUAL_JOB_NAME" --from=cronjob/$CRONJOB_NAME -n $NAMESPACE

    print_newline_with_separator

    # Add label for easier identification
    kubectl label job "$MANUAL_JOB_NAME" app=manual-backup -n $NAMESPACE

    print_newline_with_separator

    print_success "Manual job created: $MANUAL_JOB_NAME"

    print_newline_with_separator

    # Wait for job to start
    wait_for_condition "Job to start" \
        "kubectl get job $MANUAL_JOB_NAME -n $NAMESPACE -o jsonpath='{.status.active}' | grep -q '1'" \
        60 2
}

# Function to get the pod name from job
get_job_pod() {
    local job_name="$1"
    kubectl get pods -l job-name="$job_name" -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

# Function to follow job logs
follow_job_logs() {
    local job_name="$1"
    print_status "Following logs for job: $job_name"

    # Wait for pod to be created
    local pod_name=""
    local attempts=0
    while [ -z "$pod_name" ] && [ $attempts -lt 12 ]; do
        sleep 5
        pod_name=$(get_job_pod $job_name)
        attempts=$((attempts + 1))
        echo -n "."
    done

    echo ""

    if [ -z "$pod_name" ]; then
        print_error "Could not find pod for job $job_name"
        return 1
    fi

    print_success "Found pod: $pod_name"

    # Wait for pod to be ready or running
    wait_for_condition "Pod to be ready" \
        "kubectl get pod $pod_name -n $NAMESPACE -o jsonpath='{.status.phase}' | grep -E '(Running|Succeeded)'" \
        60 2

    echo ""
    echo "=== Job Logs ==="
    echo "Following logs for pod: $pod_name"
    echo "Press Ctrl+C to stop following logs"
    echo ""

    # Follow logs
    kubectl logs -f $pod_name -n $NAMESPACE 2>/dev/null || {
        print_warning "Pod may have completed. Showing final logs:"
        kubectl logs $pod_name -n $NAMESPACE
    }
}

# Function to show job status
show_job_status() {
    local job_name="$1"
    echo ""
    echo "=== Job Status ==="
    kubectl get job $job_name -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Pod Status ==="
    kubectl get pods -l job-name=$job_name -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Job Description ==="
    kubectl describe job $job_name -n $NAMESPACE

    print_newline_with_separator
}

# Function to monitor automatic CronJob execution
monitor_automatic_execution() {
    print_status "Monitoring for automatic CronJob execution..."
    print_status "The CronJob is scheduled to run every minute"
    print_status "Waiting for the next automatic execution..."

    # Get current job count
    local initial_count=$(kubectl get jobs -l job-name=$CRONJOB_NAME -n $NAMESPACE --no-headers 2>/dev/null | wc -l)

    # Wait for a new job to be created (up to 100 seconds to account for timing)
    local waited=0
    while [ $waited -lt 100 ]; do
        local current_count=$(kubectl get jobs -l job-name=$CRONJOB_NAME -n $NAMESPACE --no-headers 2>/dev/null | wc -l)

        if [ "$current_count" -gt $initial_count ]; then
            print_success "New automatic job detected!"

            # Get the latest job
            local latest_job=$(kubectl get jobs -l job-name=$CRONJOB_NAME -n $NAMESPACE --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')

            if [ -n "$latest_job" ]; then
                echo ""
                echo "=== Latest Automatic Job: $latest_job ==="
                follow_job_logs "$latest_job"
                return 0
            fi
        fi

        echo -n "."
        sleep 5
        waited=$((waited + 5))
    done

    print_warning "No automatic execution detected within 100 seconds"
    print_status "You can check manually with: kubectl get jobs -l job-name=$CRONJOB_NAME -n $NAMESPACE"

    print_newline_with_separator
}

# Function to show final status
show_final_status() {
    echo ""
    echo "=================================="
    echo "         FINAL STATUS"
    echo "=================================="

    echo ""
    echo "=== CronJob Status ==="
    kubectl get cronjob $CRONJOB_NAME -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== All Jobs from CronJob ==="
    kubectl get jobs -l job-name=$CRONJOB_NAME -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Manual Jobs ==="
    kubectl get jobs -l app=manual-backup -n $NAMESPACE -o wide 2>/dev/null || echo "No manual jobs found"

    print_newline_with_separator

    echo ""
    echo "=== Useful Commands ==="
    echo "View CronJob: kubectl describe cronjob $CRONJOB_NAME -n $NAMESPACE"
    echo "List jobs: kubectl get jobs -l job-name=$CRONJOB_NAME -n $NAMESPACE"
    echo "View logs: kubectl logs -l job-name=$CRONJOB_NAME -n $NAMESPACE"
    echo "Delete CronJob: kubectl delete cronjob $CRONJOB_NAME -n $NAMESPACE"

    print_newline_with_separator
}

# Cleanup function for script interruption
cleanup() {
    echo ""
    print_warning "Script interrupted. Current status:"
    kubectl get cronjob $CRONJOB_NAME -n $NAMESPACE 2>/dev/null || echo "CronJob not found"
    kubectl get jobs -l job-name=$CRONJOB_NAME -n $NAMESPACE 2>/dev/null || echo "No jobs found"
    exit 1
}

# Trap Ctrl+C
trap cleanup INT

# Main execution
main() {
    echo "=================================="
    echo "  CronJob Deployment & Test Script"
    echo "=================================="

    # Pre-flight checks
    check_kubectl

    # Cleanup any existing resources
    cleanup_existing

    # Deploy CronJob
    deploy_cronjob

    # Verify deployment
    verify_cronjob

    # Manually trigger job
    trigger_manual_job

    # Follow manual job logs
    follow_job_logs "$MANUAL_JOB_NAME"

    # Show manual job status
    show_job_status "$MANUAL_JOB_NAME"

    # Monitor automatic execution
    monitor_automatic_execution

    # Show final status
    show_final_status

    print_success "Script completed successfully!"

    # Cleanup YAML file
    rm -f cronjob.yaml
}

# Run main function
main "$@"
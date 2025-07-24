#!/bin/bash

# Job Creation and Testing Script
# This script creates Jobs and demonstrates different job patterns and execution modes

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MANIFEST_FILE="manifest.yml"
BATCH_JOB_NAME="batch-processing-job"
INDEXED_JOB_NAME="indexed-processing-job"
MIGRATION_JOB_NAME="database-migration-job"
QUEUE_JOB_NAME="work-queue-job"
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

    # List of jobs to clean up
    JOBS=($BATCH_JOB_NAME $INDEXED_JOB_NAME $MIGRATION_JOB_NAME $QUEUE_JOB_NAME)

    # Delete existing Jobs if they exist
    for job in "${JOBS[@]}"; do
        if kubectl get job $job -n $NAMESPACE &> /dev/null; then
            print_warning "Existing Job $job found, deleting..."
            kubectl delete job $job -n $NAMESPACE
        fi
    done

    # Clean up any lingering pods
    kubectl get pods -l app=batch-processor -n $NAMESPACE --no-headers 2>/dev/null | awk '{print $1}' | xargs -r kubectl delete pod --grace-period=0 --force -n $NAMESPACE
    kubectl get pods -l app=indexed-processor -n $NAMESPACE --no-headers 2>/dev/null | awk '{print $1}' | xargs -r kubectl delete pod --grace-period=0 --force -n $NAMESPACE

    # Wait for Jobs to be deleted
    wait_for_condition "Job cleanup" \
        "! kubectl get job $BATCH_JOB_NAME -n $NAMESPACE &> /dev/null" \
        30 2

    print_success "Cleanup completed"

    print_newline_with_separator
}

# Function to deploy Jobs
deploy_jobs() {
    print_status "Deploying Jobs..."
    kubectl apply -f ${MANIFEST_FILE} -n $NAMESPACE

    print_newline_with_separator

    # Wait for Jobs to be created
    wait_for_condition "Job creation" \
        "kubectl get job $BATCH_JOB_NAME -n $NAMESPACE &> /dev/null && kubectl get job $INDEXED_JOB_NAME -n $NAMESPACE &> /dev/null" \
        30 2

    print_success "Jobs deployed successfully"

    print_newline_with_separator
}

# Function to verify Job status
verify_jobs() {
    print_status "Verifying Job status..."

    # Check Job details
    echo ""
    echo "=== All Jobs ==="
    kubectl get jobs -n $NAMESPACE -o wide | grep -E "(batch-processing|indexed-processing|database-migration|work-queue|NAME)" || echo "No matching jobs found"

    print_newline_with_separator

    echo ""
    echo "=== Batch Processing Job Details ==="
    kubectl describe job $BATCH_JOB_NAME -n $NAMESPACE

    print_newline_with_separator

    echo ""
    echo "=== Job Pods ==="
    kubectl get pods -l app=batch-processor -n $NAMESPACE -o wide

    print_newline_with_separator

    echo ""
    echo "=== Indexed Job Pods ==="
    kubectl get pods -l app=indexed-processor -n $NAMESPACE -o wide

    print_newline_with_separator

    print_success "Jobs are created and running"

    print_newline_with_separator
}

# Function to monitor job progress
monitor_job_progress() {
    print_status "Monitoring Job progress..."

    # Monitor batch processing job
    print_status "Monitoring batch processing job..."
    
    for i in {1..12}; do  # Monitor for up to 1 minute
        echo ""
        echo "=== Job Status Check $i ==="
        
        # Get job status
        ACTIVE=$(kubectl get job $BATCH_JOB_NAME -n $NAMESPACE -o jsonpath='{.status.active}' 2>/dev/null || echo "0")
        SUCCEEDED=$(kubectl get job $BATCH_JOB_NAME -n $NAMESPACE -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
        FAILED=$(kubectl get job $BATCH_JOB_NAME -n $NAMESPACE -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
        
        echo "Batch Job Status - Active: $ACTIVE, Succeeded: $SUCCEEDED, Failed: $FAILED"
        
        # Get indexed job status
        INDEXED_ACTIVE=$(kubectl get job $INDEXED_JOB_NAME -n $NAMESPACE -o jsonpath='{.status.active}' 2>/dev/null || echo "0")
        INDEXED_SUCCEEDED=$(kubectl get job $INDEXED_JOB_NAME -n $NAMESPACE -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
        
        echo "Indexed Job Status - Active: $INDEXED_ACTIVE, Succeeded: $INDEXED_SUCCEEDED"
        
        # Check if jobs are complete
        if [ "$SUCCEEDED" -ge "5" ] && [ "$INDEXED_SUCCEEDED" -ge "8" ]; then
            print_success "Jobs completed successfully!"
            break
        fi
        
        sleep 5
    done

    print_newline_with_separator
}

# Function to show job logs
show_job_logs() {
    print_status "Showing Job logs..."

    echo ""
    echo "=== Batch Processing Job Logs ==="
    kubectl logs -l app=batch-processor -n $NAMESPACE --tail=50 | head -100 || echo "No logs available yet"

    print_newline_with_separator

    echo ""
    echo "=== Indexed Job Logs ==="
    kubectl logs -l app=indexed-processor -n $NAMESPACE --tail=30 | head -100 || echo "No logs available yet"

    print_newline_with_separator

    echo ""
    echo "=== Migration Job Logs ==="
    kubectl logs -l app=myapp,component=migration -n $NAMESPACE --tail=20 2>/dev/null || echo "Migration job not started or no logs available"

    print_newline_with_separator
}

# Function to test job completion patterns
test_job_patterns() {
    print_status "Testing different Job patterns..."

    echo ""
    echo "=== Testing Single Job Pattern ==="
    # Create a simple single completion job
    cat <<EOF | kubectl apply -f - -n $NAMESPACE
apiVersion: batch/v1
kind: Job
metadata:
  name: single-task-job
  labels:
    test: single-task
spec:
  template:
    spec:
      containers:
      - name: task
        image: busybox
        command: ['sh', '-c', 'echo "Single task job executed at $(date)"; sleep 10; echo "Task completed"']
      restartPolicy: Never
EOF

    # Wait for single job to complete
    wait_for_condition "Single job completion" \
        "kubectl get job single-task-job -n $NAMESPACE -o jsonpath='{.status.succeeded}' | grep -q '1'" \
        60 5

    echo ""
    echo "=== Single Job Logs ==="
    kubectl logs -l test=single-task -n $NAMESPACE

    # Clean up single job
    kubectl delete job single-task-job -n $NAMESPACE &

    print_newline_with_separator

    echo ""
    echo "=== Testing Manual Job Creation from CLI ==="
    
    print_status "Creating job from command line..."
    # Create job using kubectl create job command
    kubectl create job cli-created-job --image=busybox -n $NAMESPACE -- /bin/sh -c 'echo "Job created from CLI at $(date)"; sleep 5; echo "CLI job completed"'
    
    # Wait for CLI job to complete
    wait_for_condition "CLI job completion" \
        "kubectl get job cli-created-job -n $NAMESPACE -o jsonpath='{.status.succeeded}' | grep -q '1'" \
        30 5

    echo ""
    echo "=== CLI Created Job Logs ==="
    kubectl logs -l job-name=cli-created-job -n $NAMESPACE

    # Clean up CLI job
    kubectl delete job cli-created-job -n $NAMESPACE &

    print_newline_with_separator
}

# Function to test job failure handling
test_failure_handling() {
    print_status "Testing Job failure handling..."

    # Create a job that will fail initially but eventually succeed
    cat <<EOF | kubectl apply -f - -n $NAMESPACE
apiVersion: batch/v1
kind: Job
metadata:
  name: failure-test-job
  labels:
    test: failure-handling
spec:
  backoffLimit: 3
  template:
    spec:
      containers:
      - name: flaky-task
        image: busybox
        command: ['sh', '-c']
        args:
        - |
          RANDOM_NUM=\$((RANDOM % 3))
          echo "Attempt started at \$(date)"
          echo "Random number: \$RANDOM_NUM"
          
          if [ \$RANDOM_NUM -eq 0 ]; then
            echo "Task succeeded on this attempt!"
            exit 0
          else
            echo "Task failed on this attempt (random: \$RANDOM_NUM)"
            exit 1
          fi
      restartPolicy: OnFailure
EOF

    # Monitor the failing job
    print_status "Monitoring failure and retry behavior..."
    
    for i in {1..8}; do
        ACTIVE=$(kubectl get job failure-test-job -n $NAMESPACE -o jsonpath='{.status.active}' 2>/dev/null || echo "0")
        SUCCEEDED=$(kubectl get job failure-test-job -n $NAMESPACE -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
        FAILED=$(kubectl get job failure-test-job -n $NAMESPACE -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
        
        echo "Attempt $i - Active: $ACTIVE, Succeeded: $SUCCEEDED, Failed: $FAILED"
        
        if [ "$SUCCEEDED" -ge "1" ]; then
            print_success "Job eventually succeeded after retries!"
            break
        elif [ "$FAILED" -ge "3" ]; then
            print_warning "Job failed after maximum retries"
            break
        fi
        
        sleep 5
    done

    echo ""
    echo "=== Failure Test Job Logs ==="
    kubectl logs -l test=failure-handling -n $NAMESPACE --tail=50

    # Clean up failure test job
    kubectl delete job failure-test-job -n $NAMESPACE &

    print_newline_with_separator
}

# Function to demonstrate job scaling
test_job_scaling() {
    print_status "Demonstrating Job scaling..."

    # Create a job and then scale its parallelism
    cat <<EOF | kubectl apply -f - -n $NAMESPACE
apiVersion: batch/v1
kind: Job
metadata:
  name: scalable-job
  labels:
    test: scaling
spec:
  completions: 10
  parallelism: 2
  template:
    spec:
      containers:
      - name: worker
        image: busybox
        command: ['sh', '-c', 'echo "Worker \$HOSTNAME started"; sleep 15; echo "Worker \$HOSTNAME completed"']
      restartPolicy: OnFailure
EOF

    sleep 5
    
    echo ""
    echo "=== Initial Job State ==="
    kubectl get job scalable-job -n $NAMESPACE -o wide

    # Scale up parallelism
    print_status "Scaling job parallelism from 2 to 5..."
    kubectl patch job scalable-job -n $NAMESPACE -p '{"spec":{"parallelism":5}}'

    sleep 10

    echo ""
    echo "=== Scaled Job State ==="
    kubectl get job scalable-job -n $NAMESPACE -o wide
    kubectl get pods -l test=scaling -n $NAMESPACE -o wide

    # Clean up scaling test job
    kubectl delete job scalable-job -n $NAMESPACE &

    print_newline_with_separator
}

# Function to show final status
show_final_status() {
    echo ""
    echo "=================================="
    echo "         FINAL STATUS"
    echo "=================================="

    echo ""
    echo "=== All Jobs Status ==="
    kubectl get jobs -n $NAMESPACE | grep -E "(batch-processing|indexed-processing|database-migration|work-queue|NAME)" || echo "No matching jobs found"

    print_newline_with_separator

    echo ""
    echo "=== Job Completion Summary ==="
    for job in $BATCH_JOB_NAME $INDEXED_JOB_NAME $MIGRATION_JOB_NAME $QUEUE_JOB_NAME; do
        if kubectl get job $job -n $NAMESPACE &>/dev/null; then
            SUCCEEDED=$(kubectl get job $job -n $NAMESPACE -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
            FAILED=$(kubectl get job $job -n $NAMESPACE -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
            ACTIVE=$(kubectl get job $job -n $NAMESPACE -o jsonpath='{.status.active}' 2>/dev/null || echo "0")
            echo "$job: Succeeded=$SUCCEEDED, Failed=$FAILED, Active=$ACTIVE"
        else
            echo "$job: Not found"
        fi
    done

    print_newline_with_separator

    echo ""
    echo "=== Pod Status Summary ==="
    echo "Batch processing pods:"
    kubectl get pods -l app=batch-processor -n $NAMESPACE --no-headers 2>/dev/null | wc -l | xargs echo "Count:"
    
    echo "Indexed processing pods:"
    kubectl get pods -l app=indexed-processor -n $NAMESPACE --no-headers 2>/dev/null | wc -l | xargs echo "Count:"

    print_newline_with_separator

    echo ""
    echo "=== Job Events ==="
    kubectl get events --field-selector involvedObject.kind=Job -n $NAMESPACE --sort-by=.metadata.creationTimestamp | tail -10

    print_newline_with_separator

    echo ""
    echo "=== Job Patterns Demonstrated ==="
    echo "1. ✅ Parallel Job Pattern (batch-processing-job)"
    echo "2. ✅ Indexed Job Pattern (indexed-processing-job)"
    echo "3. ✅ Single Completion Pattern (database-migration-job)"
    echo "4. ✅ Work Queue Pattern (work-queue-job)"
    echo "5. ✅ Failure Handling and Retries"
    echo "6. ✅ Job Scaling"

    print_newline_with_separator

    echo ""
    echo "=== Useful Commands ==="
    echo "View Job: kubectl describe job $BATCH_JOB_NAME -n $NAMESPACE"
    echo "Job logs: kubectl logs -l job-name=$BATCH_JOB_NAME -n $NAMESPACE"
    echo "Scale job: kubectl patch job $BATCH_JOB_NAME -p '{\"spec\":{\"parallelism\":3}}'"
    echo "Suspend job: kubectl patch job $BATCH_JOB_NAME -p '{\"spec\":{\"suspend\":true}}'"
    echo "Create from CronJob: kubectl create job manual-job --from=cronjob/mycronjob"
    echo "Delete completed: kubectl delete jobs --field-selector=status.successful=1"
    echo "Monitor progress: kubectl get job $BATCH_JOB_NAME -w"

    print_newline_with_separator
}

# Cleanup function for script interruption
cleanup() {
    echo ""
    print_warning "Script interrupted. Current status:"
    kubectl get jobs -n $NAMESPACE | grep -E "(batch-processing|indexed-processing)" 2>/dev/null || echo "No jobs found"
    kubectl get pods -l app=batch-processor -n $NAMESPACE 2>/dev/null || echo "No pods found"
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    exit 1
}

# Trap Ctrl+C
trap cleanup INT

# Main execution
main() {
    echo "=================================="
    echo "     Job Creation & Test Script"
    echo "=================================="

    # Pre-flight checks
    check_kubectl

    # Cleanup any existing resources
    cleanup_existing

    # Deploy Jobs
    deploy_jobs

    # Verify Jobs
    verify_jobs

    # Monitor job progress
    monitor_job_progress

    # Show job logs
    show_job_logs

    # Test job patterns
    test_job_patterns

    # Test failure handling
    test_failure_handling

    # Test job scaling
    test_job_scaling

    # Show final status
    show_final_status

    print_success "Script completed successfully!"

    echo ""
    echo "Jobs have been created and tested successfully."
    echo "You can now see various Job patterns in action."
}

# Run main function
main "$@"
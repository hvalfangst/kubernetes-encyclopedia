# Kubernetes Job Resource Documentation

## Table of Contents
- [Overview](#overview)
- [API Specification](#api-specification)
- [Field Reference](#field-reference)
- [Job Patterns](#job-patterns)
- [Completion Modes](#completion-modes)
- [Failure Handling](#failure-handling)
- [Common Use Cases](#common-use-cases)
- [Best Practices](#best-practices)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

## Overview

A **Job** represents one-off tasks that run to completion and then stop. A Job creates one or more Pods and retries execution until a specified number successfully complete.

### Key Features
- Run-to-completion workloads
- Automatic retry mechanism with backoff
- Parallel and sequential execution modes
- Indexed jobs for work queue patterns
- Automatic cleanup of completed jobs
- Integration with CronJob for scheduled execution

### When to Use Jobs
- **Batch processing**: Data processing and ETL operations
- **Database migrations**: Schema updates and data migrations
- **Backup operations**: Database and file system backups
- **Image processing**: Batch image or video processing
- **Machine learning**: Training jobs and data analysis
- **One-time tasks**: Setup, initialization, and cleanup tasks

## API Specification

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: string
  namespace: string
  labels: {}
  annotations: {}
spec:
  parallelism: integer                 # Max concurrent pods (default: 1)
  completions: integer                 # Required successful completions (default: 1)
  completionMode: string               # NonIndexed or Indexed
  backoffLimit: integer                # Max retries before failure (default: 6)
  activeDeadlineSeconds: integer       # Max job duration
  ttlSecondsAfterFinished: integer     # Cleanup delay after completion
  suspend: boolean                     # Pause job execution
  selector:                           # Pod selector
    matchLabels: {}
  template:                           # Required: Pod template
    metadata:
      labels: {}
    spec: {}
  manualSelector: boolean             # Manual pod selector control
status:
  conditions: []                      # Job conditions
  startTime: string                   # Job start time
  completionTime: string              # Job completion time
  active: integer                     # Number of active pods
  succeeded: integer                  # Number of succeeded pods
  failed: integer                     # Number of failed pods
  completedIndexes: string            # Completed indexes (Indexed mode)
```

## Field Reference

### Metadata Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Name of the Job resource |
| `namespace` | string | Namespace where the Job resides |
| `labels` | map[string]string | Key-value pairs for organizing resources |
| `annotations` | map[string]string | Additional metadata for the resource |

### Spec Fields

#### parallelism
**Type**: `integer`  
**Default**: `1`  
**Description**: Maximum number of pods running concurrently

```yaml
spec:
  parallelism: 3  # Run up to 3 pods simultaneously
```

**Use Cases**:
- **High throughput**: Process large datasets faster
- **Resource optimization**: Balance speed vs resource usage
- **Parallel processing**: Independent work items

#### completions
**Type**: `integer`  
**Default**: `1`  
**Description**: Number of successful pod completions required

```yaml
spec:
  completions: 5  # Need 5 successful completions
  parallelism: 2  # Run 2 at a time
```

**Patterns**:
- **Single completion** (1): One-off tasks
- **Fixed completions** (N): Process N work items
- **No completions** (null): Run until stopped

#### completionMode
**Type**: `string`  
**Default**: `NonIndexed`  
**Options**: `NonIndexed`, `Indexed`

**NonIndexed**: Pods are interchangeable
**Indexed**: Each pod gets a unique index (0 to completions-1)

```yaml
spec:
  completionMode: Indexed
  completions: 3
  parallelism: 2
  template:
    spec:
      containers:
      - name: worker
        image: worker:latest
        env:
        - name: JOB_COMPLETION_INDEX
          valueFrom:
            fieldRef:
              fieldPath: metadata.annotations['batch.kubernetes.io/job-completion-index']
```

#### backoffLimit
**Type**: `integer`  
**Default**: `6`  
**Description**: Number of retries before marking job as failed

```yaml
spec:
  backoffLimit: 3  # Retry up to 3 times
```

**Retry Behavior**:
- Exponential backoff between retries
- Failed pods are recreated
- Job fails after reaching backoff limit

#### activeDeadlineSeconds
**Type**: `integer`  
**Description**: Maximum time for job to run before termination

```yaml
spec:
  activeDeadlineSeconds: 3600  # 1 hour timeout
```

#### ttlSecondsAfterFinished
**Type**: `integer`  
**Description**: Time to live after job completion (automatic cleanup)

```yaml
spec:
  ttlSecondsAfterFinished: 86400  # Delete after 24 hours
```

#### suspend
**Type**: `boolean`  
**Default**: `false`  
**Description**: Suspend job execution

```yaml
spec:
  suspend: true  # Pause job execution
```

## Job Patterns

### Single Pod Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: single-task
spec:
  template:
    spec:
      containers:
      - name: task
        image: busybox
        command: ['sh', '-c', 'echo "Single task completed"']
      restartPolicy: Never
```

### Parallel Jobs with Fixed Completion Count

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: parallel-job
spec:
  completions: 8      # Need 8 successful completions
  parallelism: 2      # Run 2 pods at a time
  template:
    spec:
      containers:
      - name: worker
        image: worker:latest
        command: ['./process-work-item.sh']
      restartPolicy: OnFailure
```

### Work Queue Pattern

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: work-queue
spec:
  parallelism: 3      # 3 workers
  # No completions specified - runs until queue is empty
  template:
    spec:
      containers:
      - name: worker
        image: worker:latest
        env:
        - name: QUEUE_URL
          value: "redis://queue:6379"
        command: ['./process-queue.sh']
      restartPolicy: OnFailure
```

### Indexed Job Pattern

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: indexed-job
spec:
  completionMode: Indexed
  completions: 10     # Process items 0-9
  parallelism: 3      # 3 workers at a time
  template:
    spec:
      containers:
      - name: worker
        image: worker:latest
        command: ['./process-indexed-item.sh']
        env:
        - name: JOB_COMPLETION_INDEX
          valueFrom:
            fieldRef:
              fieldPath: metadata.annotations['batch.kubernetes.io/job-completion-index']
      restartPolicy: OnFailure
```

## Completion Modes

### NonIndexed Mode (Default)

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: nonindexed-job
spec:
  completionMode: NonIndexed
  completions: 5
  parallelism: 2
  template:
    spec:
      containers:
      - name: worker
        image: data-processor:latest
        command: ['./process-batch.sh']
        env:
        - name: WORKER_ID
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
      restartPolicy: OnFailure
```

### Indexed Mode

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: indexed-batch-job
spec:
  completionMode: Indexed
  completions: 100    # Process files 0-99
  parallelism: 10     # 10 parallel workers
  template:
    spec:
      containers:
      - name: processor
        image: file-processor:latest
        command: ['sh', '-c']
        args:
        - |
          INDEX=${JOB_COMPLETION_INDEX}
          FILE="input-${INDEX}.dat"
          echo "Processing $FILE"
          ./process-file.sh $FILE
        env:
        - name: JOB_COMPLETION_INDEX
          valueFrom:
            fieldRef:
              fieldPath: metadata.annotations['batch.kubernetes.io/job-completion-index']
        - name: S3_BUCKET
          value: "data-processing-bucket"
        volumeMounts:
        - name: work-dir
          mountPath: /workspace
      volumes:
      - name: work-dir
        emptyDir: {}
      restartPolicy: OnFailure
```

## Failure Handling

### Basic Retry Configuration

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: retry-job
spec:
  backoffLimit: 5     # Retry up to 5 times
  activeDeadlineSeconds: 1800  # 30 minute timeout
  template:
    spec:
      containers:
      - name: worker
        image: unreliable-service:latest
        command: ['./flaky-process.sh']
        env:
        - name: MAX_RETRIES
          value: "3"
        - name: RETRY_DELAY
          value: "10"
      restartPolicy: OnFailure  # Important for retries
```

### Advanced Failure Handling

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: robust-job
spec:
  backoffLimit: 10
  activeDeadlineSeconds: 7200  # 2 hours
  template:
    spec:
      containers:
      - name: worker
        image: robust-worker:latest
        command: ['sh', '-c']
        args:
        - |
          set -e
          
          # Implement application-level retries
          for i in $(seq 1 3); do
            if ./main-process.sh; then
              echo "Success on attempt $i"
              exit 0
            else
              echo "Attempt $i failed, retrying..."
              sleep $((i * 10))  # Exponential backoff
            fi
          done
          
          echo "All attempts failed"
          exit 1
        env:
        - name: TIMEOUT
          value: "300"
        - name: LOG_LEVEL
          value: "DEBUG"
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          exec:
            command: ['./health-check.sh']
          initialDelaySeconds: 30
          periodSeconds: 60
      restartPolicy: OnFailure
```

## Common Use Cases

### Database Migration

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
  labels:
    app: myapp
    component: migration
spec:
  backoffLimit: 2  # Migrations should not be retried too many times
  activeDeadlineSeconds: 3600  # 1 hour limit
  template:
    spec:
      containers:
      - name: migrator
        image: myapp/migrator:v1.2.0
        command: ['./migrate.sh']
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: url
        - name: MIGRATION_DIR
          value: "/migrations"
        volumeMounts:
        - name: migrations
          mountPath: /migrations
          readOnly: true
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
      volumes:
      - name: migrations
        configMap:
          name: migration-scripts
      restartPolicy: Never  # Never retry migrations
```

### Batch Data Processing

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: data-processing
  labels:
    app: analytics
    batch-id: "20231001"
spec:
  completions: 24     # Process 24 hours of data
  parallelism: 4      # 4 parallel processors
  completionMode: Indexed
  backoffLimit: 3
  activeDeadlineSeconds: 14400  # 4 hours
  ttlSecondsAfterFinished: 259200  # Clean up after 3 days
  template:
    spec:
      containers:
      - name: processor
        image: data-analytics:v2.1
        command: ['python', 'process_hour.py']
        args: ['--hour', '$(JOB_COMPLETION_INDEX)']
        env:
        - name: JOB_COMPLETION_INDEX
          valueFrom:
            fieldRef:
              fieldPath: metadata.annotations['batch.kubernetes.io/job-completion-index']
        - name: BATCH_DATE
          value: "2023-10-01"
        - name: S3_INPUT_BUCKET
          value: "raw-data"
        - name: S3_OUTPUT_BUCKET
          value: "processed-data"
        - name: AWS_REGION
          value: "us-west-2"
        envFrom:
        - secretRef:
            name: aws-credentials
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
        volumeMounts:
        - name: temp-storage
          mountPath: /tmp/processing
      volumes:
      - name: temp-storage
        emptyDir:
          sizeLimit: 10Gi
      restartPolicy: OnFailure
```

### Image Processing Pipeline

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: image-processing-pipeline
  labels:
    pipeline: image-processing
    version: v1
spec:
  completions: 1000   # Process 1000 images
  parallelism: 20     # 20 parallel processors
  completionMode: Indexed
  backoffLimit: 5
  activeDeadlineSeconds: 10800  # 3 hours
  template:
    spec:
      containers:
      - name: image-processor
        image: image-pipeline:v1.5
        command: ['./process-image.sh']
        env:
        - name: IMAGE_INDEX
          valueFrom:
            fieldRef:
              fieldPath: metadata.annotations['batch.kubernetes.io/job-completion-index']
        - name: INPUT_BUCKET
          value: "raw-images"
        - name: OUTPUT_BUCKET
          value: "processed-images"
        - name: PROCESSING_PROFILE
          value: "high-quality"
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        volumeMounts:
        - name: temp-images
          mountPath: /tmp/images
      volumes:
      - name: temp-images
        emptyDir:
          sizeLimit: 5Gi
      restartPolicy: OnFailure
```

### Backup Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: database-backup
  labels:
    app: postgres
    backup-type: full
spec:
  backoffLimit: 2
  activeDeadlineSeconds: 7200  # 2 hours for large databases
  ttlSecondsAfterFinished: 86400  # Keep job for 24 hours
  template:
    spec:
      containers:
      - name: backup
        image: postgres:15
        command: ['sh', '-c']
        args:
        - |
          set -e
          BACKUP_FILE="backup-$(date +%Y%m%d-%H%M%S).sql"
          echo "Starting backup: $BACKUP_FILE"
          
          pg_dump $DATABASE_URL > /backups/$BACKUP_FILE
          
          # Compress backup
          gzip /backups/$BACKUP_FILE
          
          # Upload to S3 (if aws cli available)
          if command -v aws >/dev/null 2>&1; then
            aws s3 cp /backups/$BACKUP_FILE.gz s3://$BACKUP_BUCKET/
          fi
          
          echo "Backup completed: $BACKUP_FILE.gz"
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: url
        - name: BACKUP_BUCKET
          value: "db-backups"
        envFrom:
        - secretRef:
            name: aws-credentials
        volumeMounts:
        - name: backup-storage
          mountPath: /backups
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
      volumes:
      - name: backup-storage
        persistentVolumeClaim:
          claimName: backup-pvc
      restartPolicy: OnFailure
```

## Best Practices

### Resource Management

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: resource-managed-job
spec:
  parallelism: 5
  completions: 20
  backoffLimit: 3
  activeDeadlineSeconds: 3600
  template:
    spec:
      containers:
      - name: worker
        image: worker:latest
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "500m"
        # Resource-aware processing
        env:
        - name: MEMORY_LIMIT
          valueFrom:
            resourceFieldRef:
              resource: limits.memory
        - name: CPU_LIMIT
          valueFrom:
            resourceFieldRef:
              resource: limits.cpu
      restartPolicy: OnFailure
      # Prevent job pods from being scheduled on same node
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: job-name
                  operator: In
                  values: ["resource-managed-job"]
              topologyKey: kubernetes.io/hostname
```

### Monitoring and Observability

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: monitored-job
  labels:
    app: data-processor
    version: v2.0
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
spec:
  parallelism: 3
  completions: 10
  template:
    spec:
      containers:
      - name: worker
        image: monitored-worker:v2.0
        ports:
        - containerPort: 8080
          name: metrics
        env:
        - name: ENABLE_METRICS
          value: "true"
        - name: JOB_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.labels['job-name']
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 60
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
      restartPolicy: OnFailure
```

### Security Configuration

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: secure-job
spec:
  template:
    spec:
      serviceAccountName: job-service-account
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 2000
      containers:
      - name: worker
        image: secure-worker:latest
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          capabilities:
            drop: ["ALL"]
        volumeMounts:
        - name: tmp
          mountPath: /tmp
        - name: secrets
          mountPath: /etc/secrets
          readOnly: true
      volumes:
      - name: tmp
        emptyDir: {}
      - name: secrets
        secret:
          secretName: job-secrets
          defaultMode: 0400
      restartPolicy: OnFailure
```

## Troubleshooting

### Common Issues

#### 1. Job Not Starting

```bash
# Check Job status
kubectl get job myjob -o wide

# Check Job events
kubectl describe job myjob

# Check Pod status
kubectl get pods -l job-name=myjob

# Check Pod events
kubectl describe pod <pod-name>

# Check resource quotas
kubectl describe quota
kubectl describe limitrange
```

#### 2. Job Pods Failing

```bash
# Check Pod logs
kubectl logs -l job-name=myjob

# Check previous Pod logs if Pod restarted
kubectl logs -l job-name=myjob --previous

# Check Job conditions
kubectl get job myjob -o yaml | grep -A 10 conditions

# Check backoff limit
kubectl get job myjob -o jsonpath='{.spec.backoffLimit}'
kubectl get job myjob -o jsonpath='{.status.failed}'
```

#### 3. Job Stuck or Not Completing

```bash
# Check active deadline
kubectl get job myjob -o jsonpath='{.spec.activeDeadlineSeconds}'

# Check job progress
kubectl get job myjob -o jsonpath='{.status.active}'
kubectl get job myjob -o jsonpath='{.status.succeeded}'

# Check if job is suspended
kubectl get job myjob -o jsonpath='{.spec.suspend}'

# Manual cleanup if needed
kubectl delete job myjob --cascade=foreground
```

### Debugging Commands

```bash
# List all jobs
kubectl get jobs
kubectl get jobs --all-namespaces

# Get job details
kubectl describe job myjob

# Check job status
kubectl get job myjob -o yaml

# View job logs
kubectl logs -l job-name=myjob
kubectl logs -l job-name=myjob --tail=100

# Get job pods
kubectl get pods -l job-name=myjob

# Check job history
kubectl get events --field-selector involvedObject.name=myjob

# Create job from CronJob
kubectl create job manual-job --from=cronjob/mycronjob

# Suspend/resume job
kubectl patch job myjob -p '{"spec":{"suspend":true}}'
kubectl patch job myjob -p '{"spec":{"suspend":false}}'

# Scale job parallelism
kubectl patch job myjob -p '{"spec":{"parallelism":5}}'

# Delete completed jobs
kubectl delete jobs --field-selector=status.successful=1

# Monitor job progress
kubectl get job myjob -w
```

### Performance Optimization

```bash
# Check resource usage
kubectl top pods -l job-name=myjob

# Monitor job metrics
kubectl get --raw /apis/metrics.k8s.io/v1beta1/namespaces/default/pods \
  | jq '.items[] | select(.metadata.labels["job-name"]=="myjob")'

# Check node resource availability
kubectl describe nodes | grep -A 5 "Allocated resources"

# Optimize parallelism based on cluster capacity
kubectl get nodes --no-headers | wc -l  # Number of nodes
kubectl describe nodes | grep -E "cpu:|memory:" | head -10
```

---

## References

- [Kubernetes Official Documentation: Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [Kubernetes API Reference: Job](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.28/#job-v1-batch)
- [Job Patterns Guide](https://kubernetes.io/docs/concepts/workloads/controllers/job/#job-patterns)
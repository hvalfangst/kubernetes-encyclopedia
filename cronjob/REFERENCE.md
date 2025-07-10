# Kubernetes CronJob Resource Documentation

## Table of Contents
- [Overview](#overview)
- [API Specification](#api-specification)
- [Field Reference](#field-reference)
- [Scheduling](#scheduling)
- [Job Template Configuration](#job-template-configuration)
- [Common Use Cases](#common-use-cases)
- [Best Practices](#best-practices)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

## Overview

A **CronJob** creates Jobs on a repeating schedule. It runs a pod periodically on a given schedule, written in Cron format. CronJobs are useful for creating periodic and recurring tasks, like running backups or sending emails.

### Key Features
- Schedule-based job execution using cron syntax
- Automatic job cleanup and history management
- Configurable concurrency policies
- Support for job deadlines and retries
- Built-in monitoring and logging

### When to Use CronJobs
- **Database backups**: Regular automated backups
- **Data processing**: Periodic ETL jobs or data cleanup
- **Monitoring**: Health checks and system monitoring
- **Batch processing**: Scheduled batch jobs
- **Maintenance tasks**: Log rotation, cache cleanup
- **Report generation**: Daily, weekly, or monthly reports

## API Specification

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: string
  namespace: string
  labels: {}
  annotations: {}
spec:
  schedule: string                    # Required: Cron schedule expression
  jobTemplate:                        # Required: Job template
    spec: {}
  concurrencyPolicy: string          # Optional: Allow, Forbid, Replace
  suspend: boolean                    # Optional: Pause/resume the CronJob
  successfulJobsHistoryLimit: integer # Optional: Number of successful jobs to retain
  failedJobsHistoryLimit: integer     # Optional: Number of failed jobs to retain
  startingDeadlineSeconds: integer    # Optional: Deadline for starting missed jobs
  timeZone: string                    # Optional: Time zone for the schedule
status:
  active: []                          # Currently running jobs
  lastScheduleTime: string            # Last time a job was scheduled
  lastSuccessfulTime: string          # Last time a job completed successfully
```

## Field Reference

### Metadata Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Name of the CronJob resource |
| `namespace` | string | Namespace where the CronJob resides |
| `labels` | map[string]string | Key-value pairs for organizing resources |
| `annotations` | map[string]string | Additional metadata for the resource |

### Spec Fields

#### schedule (Required)
**Type**: `string`  
**Description**: Cron schedule expression defining when to run the job

```yaml
schedule: "0 2 * * *"  # Daily at 2:00 AM
```

**Cron Format**: `minute hour day month day-of-week`
- `minute`: 0-59
- `hour`: 0-23
- `day`: 1-31
- `month`: 1-12
- `day-of-week`: 0-6 (0 = Sunday)



#### jobTemplate (Required)
**Type**: `JobTemplateSpec`  
**Description**: Template for the Job that will be created

```yaml
jobTemplate:
  spec:
    template:
      spec:
        containers:
        - name: job-container
          image: busybox
          command: ["echo", "Hello World"]
        restartPolicy: OnFailure
```

### concurrencyPolicy

**Type**: `string`  
**Default**: `Allow`  
**Options**: `Allow`, `Forbid`, `Replace`

Controls how concurrent executions of jobs are handled when the previous job is still running.

#### Use Cases & Examples:

**`Allow` (Default)**
- **Use Case**: When jobs are independent and can run simultaneously
- **Example**: Log rotation jobs that process different log files
- **Scenario**: Multiple data processing jobs that don't interfere with each other

```yaml
# Example: Multiple backup jobs can run simultaneously
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup-different-databases
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  concurrencyPolicy: Allow
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: backup-tool:latest
            command: ["backup-script.sh"]
```

**`Forbid`**
- **Use Case**: When jobs must run sequentially and overlap could cause issues
- **Example**: Database maintenance, exclusive file processing, resource-intensive tasks
- **Scenario**: ETL jobs that modify the same data source

```yaml
# Example: Database maintenance that shouldn't run concurrently
apiVersion: batch/v1
kind: CronJob
metadata:
  name: database-maintenance
spec:
  schedule: "0 1 * * 0"  # Weekly on Sunday at 1 AM
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: db-maintenance
            image: postgres:13
            command: ["psql", "-c", "VACUUM ANALYZE;"]
```

**`Replace`**
- **Use Case**: When newer jobs are more important than older ones
- **Example**: Real-time data synchronization, health checks, monitoring tasks
- **Scenario**: Stock price updates where latest data is most important

```yaml
# Example: Real-time data sync where latest job is most important
apiVersion: batch/v1
kind: CronJob
metadata:
  name: stock-price-sync
spec:
  schedule: "*/5 * * * *"  # Every 5 minutes
  concurrencyPolicy: Replace
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: sync
            image: stock-sync:latest
            command: ["sync-latest-prices.sh"]
```

---

### suspend

**Type**: `boolean`  
**Default**: `false`

Temporarily pause the CronJob without deleting it.

#### Use Cases & Examples:

**When to Use**:
- **Maintenance Windows**: Pause jobs during system maintenance
- **Debugging**: Stop jobs while investigating issues
- **Resource Management**: Temporarily reduce cluster load
- **Deployment Cycles**: Pause jobs during application deployments

```yaml
# Example: Pause during maintenance window
apiVersion: batch/v1
kind: CronJob
metadata:
  name: data-processing
spec:
  schedule: "0 */4 * * *"  # Every 4 hours
  suspend: true  # Temporarily suspended
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: processor
            image: data-processor:latest
```

**Practical Usage**:
```bash
# Suspend a CronJob
kubectl patch cronjob data-processing -p '{"spec":{"suspend":true}}'

# Resume a CronJob
kubectl patch cronjob data-processing -p '{"spec":{"suspend":false}}'
```

---

### successfulJobsHistoryLimit

**Type**: `integer`  
**Default**: `3`

Number of successful completed jobs to retain for history and debugging.

#### Use Cases & Examples:

**Low Values (1-2)**:
- **Use Case**: Production environments with many CronJobs
- **Benefit**: Reduces etcd storage usage
- **Example**: Simple health checks, log cleanup jobs

```yaml
# Example: Minimal history for simple cleanup tasks
apiVersion: batch/v1
kind: CronJob
metadata:
  name: temp-file-cleanup
spec:
  schedule: "0 * * * *"  # Hourly
  successfulJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: cleanup
            image: alpine:latest
            command: ["rm", "-rf", "/tmp/*"]
```

**High Values (5-10)**:
- **Use Case**: Critical jobs requiring detailed audit trails
- **Benefit**: Better debugging and monitoring capabilities
- **Example**: Financial data processing, compliance reports

```yaml
# Example: Keep more history for critical financial jobs
apiVersion: batch/v1
kind: CronJob
metadata:
  name: financial-report
spec:
  schedule: "0 9 * * MON"  # Monday at 9 AM
  successfulJobsHistoryLimit: 10
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: report-generator
            image: financial-reports:latest
```

---

### failedJobsHistoryLimit

**Type**: `integer`  
**Default**: `1`

Number of failed jobs to retain for debugging.

#### Use Cases & Examples:

**Higher Values (3-5)**:
- **Use Case**: Jobs prone to intermittent failures
- **Benefit**: Better pattern analysis for debugging
- **Example**: Network-dependent jobs, external API calls

```yaml
# Example: Keep more failed job history for network-dependent tasks
apiVersion: batch/v1
kind: CronJob
metadata:
  name: api-data-sync
spec:
  schedule: "*/15 * * * *"  # Every 15 minutes
  failedJobsHistoryLimit: 5
  successfulJobsHistoryLimit: 2
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: api-sync
            image: api-client:latest
            command: ["curl", "-f", "https://api.example.com/sync"]
```

**Lower Values (1)**:
- **Use Case**: Stable, well-tested jobs
- **Benefit**: Reduced storage usage
- **Example**: Internal system maintenance

---

### startingDeadlineSeconds

**Type**: `integer`  
**Description**: Deadline in seconds for starting a job if it misses scheduled time

#### Use Cases & Examples:

**Short Deadlines (60-300 seconds)**:
- **Use Case**: Time-sensitive jobs where late execution is useless
- **Example**: Real-time alerts, market data processing
- **Scenario**: If system is down during scheduled time, skip the job

```yaml
# Example: Skip job if it can't start within 5 minutes
apiVersion: batch/v1
kind: CronJob
metadata:
  name: market-alert
spec:
  schedule: "0 9 * * 1-5"  # Weekdays at 9 AM
  startingDeadlineSeconds: 300  # 5 minutes
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: alert
            image: market-alerts:latest
            command: ["send-market-open-alert.sh"]
```

**Long Deadlines (3600+ seconds)**:
- **Use Case**: Important jobs that should eventually run
- **Example**: Daily backups, monthly reports
- **Scenario**: Allow jobs to start late but ensure they run

```yaml
# Example: Allow backup to start up to 4 hours late
apiVersion: batch/v1
kind: CronJob
metadata:
  name: daily-backup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  startingDeadlineSeconds: 14400  # 4 hours
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: backup-tool:latest
            command: ["backup-database.sh"]
```

---

### timeZone

**Type**: `string`  
**Description**: Time zone for the schedule (Kubernetes 1.24+)

#### Use Cases & Examples:

**Business Hours Alignment**:
- **Use Case**: Jobs that must run during specific business hours
- **Example**: Reports for specific regional offices
- **Scenario**: Ensure jobs run at correct local time regardless of cluster timezone

```yaml
# Example: Generate reports for New York office during business hours
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ny-business-report
spec:
  schedule: "0 9 * * 1-5"  # 9 AM weekdays
  timeZone: "America/New_York"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: report
            image: business-reports:latest
            env:
            - name: REGION
              value: "NEW_YORK"
```

**Multi-Region Deployments**:
```yaml
# Example: Different CronJobs for different regions
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: london-daily-report
spec:
  schedule: "0 8 * * 1-5"  # 8 AM London time
  timeZone: "Europe/London"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: report
            image: regional-reports:latest
            env:
            - name: REGION
              value: "LONDON"
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: tokyo-daily-report
spec:
  schedule: "0 8 * * 1-5"  # 8 AM Tokyo time
  timeZone: "Asia/Tokyo"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: report
            image: regional-reports:latest
            env:
            - name: REGION
              value: "TOKYO"
```

---

### activeDeadlineSeconds

**Type**: `integer`  
**Description**: Maximum duration for the job to run before being terminated

#### Use Cases & Examples:

**Short Timeouts (300-1800 seconds)**:
- **Use Case**: Quick maintenance tasks, health checks
- **Example**: System health validation, cache warmup
- **Scenario**: Prevent runaway processes from consuming resources

```yaml
# Example: Health check that should complete quickly
apiVersion: batch/v1
kind: CronJob
metadata:
  name: system-health-check
spec:
  schedule: "*/5 * * * *"  # Every 5 minutes
  jobTemplate:
    spec:
      activeDeadlineSeconds: 300  # 5 minutes max
      template:
        spec:
          containers:
          - name: health-check
            image: health-checker:latest
            command: ["check-system-health.sh"]
```

**Long Timeouts (3600+ seconds)**:
- **Use Case**: Large data processing, backups, batch jobs
- **Example**: Database dumps, large file processing
- **Scenario**: Allow enough time for completion but prevent infinite running

```yaml
# Example: Large database backup with generous timeout
apiVersion: batch/v1
kind: CronJob
metadata:
  name: full-database-backup
spec:
  schedule: "0 1 * * 0"  # Weekly on Sunday at 1 AM
  jobTemplate:
    spec:
      activeDeadlineSeconds: 14400  # 4 hours max
      template:
        spec:
          containers:
          - name: backup
            image: postgres:13
            command: ["pg_dump", "--verbose", "--format=custom"]
            resources:
              requests:
                memory: "2Gi"
                cpu: "1"
```

---

### backoffLimit

**Type**: `integer`  
**Default**: `6`

Number of retries before considering job failed.

#### Use Cases & Examples:

**Low Retry Counts (1-2)**:
- **Use Case**: Jobs that should fail fast
- **Example**: Configuration validation, resource checks
- **Scenario**: Immediate feedback needed, retries unlikely to help

```yaml
# Example: Configuration validation that should fail fast
apiVersion: batch/v1
kind: CronJob
metadata:
  name: config-validation
spec:
  schedule: "0 * * * *"  # Hourly
  jobTemplate:
    spec:
      backoffLimit: 1  # Fail fast
      template:
        spec:
          containers:
          - name: validator
            image: config-validator:latest
            command: ["validate-config.sh"]
```

**High Retry Counts (5-10)**:
- **Use Case**: Network-dependent jobs with transient failures
- **Example**: API calls, external service interactions
- **Scenario**: Temporary network issues, rate limiting

```yaml
# Example: API synchronization with retry logic
apiVersion: batch/v1
kind: CronJob
metadata:
  name: api-sync
spec:
  schedule: "*/10 * * * *"  # Every 10 minutes
  jobTemplate:
    spec:
      backoffLimit: 8  # Allow multiple retries for network issues
      template:
        spec:
          containers:
          - name: sync
            image: api-client:latest
            command: ["sync-with-external-api.sh"]
            env:
            - name: RETRY_DELAY
              value: "30"  # 30 seconds between retries
```

---

### completions

**Type**: `integer`  
**Default**: `1`

Number of pod completions required for the job to be considered successful.

#### Use Cases & Examples:

**Single Completion (1)**:
- **Use Case**: Standard single-task jobs
- **Example**: Database backup, report generation
- **Scenario**: One successful execution is sufficient

```yaml
# Example: Standard backup job
apiVersion: batch/v1
kind: CronJob
metadata:
  name: single-backup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      completions: 1
      template:
        spec:
          containers:
          - name: backup
            image: backup-tool:latest
```

**Multiple Completions (2+)**:
- **Use Case**: Distributed processing, redundancy requirements
- **Example**: Data validation, distributed calculations
- **Scenario**: Need multiple successful runs for reliability

```yaml
# Example: Distributed data validation requiring multiple completions
apiVersion: batch/v1
kind: CronJob
metadata:
  name: distributed-validation
spec:
  schedule: "0 3 * * *"  # Daily at 3 AM
  jobTemplate:
    spec:
      completions: 3        # Need 3 successful completions
      parallelism: 3        # Run all 3 in parallel
      template:
        spec:
          containers:
          - name: validator
            image: data-validator:latest
            command: ["validate-data-subset.sh"]
            env:
            - name: SUBSET_ID
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
```

---

### parallelism

**Type**: `integer`  
**Default**: `1`

Maximum number of pods running in parallel.

#### Use Cases & Examples:

**Single Pod (1)**:
- **Use Case**: Resource-intensive jobs, sequential processing
- **Example**: Large database operations, memory-intensive tasks
- **Scenario**: Prevent resource contention

```yaml
# Example: Memory-intensive data processing
apiVersion: batch/v1
kind: CronJob
metadata:
  name: memory-intensive-job
spec:
  schedule: "0 0 * * *"  # Daily at midnight
  jobTemplate:
    spec:
      parallelism: 1  # Single pod to avoid memory pressure
      template:
        spec:
          containers:
          - name: processor
            image: data-processor:latest
            resources:
              requests:
                memory: "8Gi"
                cpu: "4"
```

**Multiple Pods (2+)**:
- **Use Case**: Parallel data processing, distributed workloads
- **Example**: Image processing, batch data transformation
- **Scenario**: Speed up processing by parallelization

```yaml
# Example: Parallel image processing
apiVersion: batch/v1
kind: CronJob
metadata:
  name: image-processing
spec:
  schedule: "0 4 * * *"  # Daily at 4 AM
  jobTemplate:
    spec:
      completions: 10       # Process 10 batches total
      parallelism: 5        # 5 pods working simultaneously
      template:
        spec:
          containers:
          - name: image-processor
            image: image-processor:latest
            command: ["process-image-batch.sh"]
            env:
            - name: BATCH_SIZE
              value: "100"
```

---

### ttlSecondsAfterFinished

**Type**: `integer`  
**Description**: Time to live for finished jobs (automatic cleanup)

#### Use Cases & Examples:

**Short TTL (300-3600 seconds)**:
- **Use Case**: Frequent jobs where old results aren't needed
- **Example**: Health checks, monitoring tasks
- **Scenario**: Reduce cluster overhead from job accumulation

```yaml
# Example: Frequent health checks with short TTL
apiVersion: batch/v1
kind: CronJob
metadata:
  name: health-monitoring
spec:
  schedule: "*/2 * * * *"  # Every 2 minutes
  jobTemplate:
    spec:
      ttlSecondsAfterFinished: 600  # Clean up after 10 minutes
      template:
        spec:
          containers:
          - name: health-check
            image: health-monitor:latest
            command: ["check-health.sh"]
```

**Long TTL (86400+ seconds)**:
- **Use Case**: Jobs where historical data is valuable
- **Example**: Backups, compliance reports
- **Scenario**: Keep results for audit trails

```yaml
# Example: Compliance backup with long retention
apiVersion: batch/v1
kind: CronJob
metadata:
  name: compliance-backup
spec:
  schedule: "0 1 * * *"  # Daily at 1 AM
  jobTemplate:
    spec:
      ttlSecondsAfterFinished: 2592000  # 30 days
      template:
        spec:
          containers:
          - name: backup
            image: compliance-backup:latest
            command: ["backup-compliance-data.sh"]
```

---

## Scheduling

### Cron Expression Examples

| Expression | Description |
|------------|-------------|
| `"0 0 * * *"` | Daily at midnight |
| `"30 2 * * *"` | Daily at 2:30 AM |
| `"0 */6 * * *"` | Every 6 hours |
| `"*/15 * * * *"` | Every 15 minutes |
| `"0 9 * * 1-5"` | 9 AM on weekdays |
| `"0 2 1 * *"` | 2 AM on the 1st of every month |
| `"0 0 * * 0"` | Every Sunday at midnight |

### Special Expressions

| Expression | Description |
|------------|-------------|
| `@yearly` or `@annually` | `0 0 1 1 *` |
| `@monthly` | `0 0 1 * *` |
| `@weekly` | `0 0 * * 0` |
| `@daily` or `@midnight` | `0 0 * * *` |
| `@hourly` | `0 * * * *` |


### Job with Resource Limits

```yaml
jobTemplate:
  spec:
    template:
      spec:
        containers:
        - name: processor
          image: python:3.9
          resources:
            requests:
              memory: "256Mi"
              cpu: "250m"
            limits:
              memory: "512Mi"
              cpu: "500m"
          command: ["python", "process.py"]
        restartPolicy: OnFailure
```

### Job with Volumes

```yaml
jobTemplate:
  spec:
    template:
      spec:
        containers:
        - name: backup
          image: busybox
          volumeMounts:
          - name: backup-storage
            mountPath: /backup
          command: ["tar", "-czf", "/backup/backup.tar.gz", "/data"]
        volumes:
        - name: backup-storage
          persistentVolumeClaim:
            claimName: backup-pvc
        restartPolicy: OnFailure
```

## Troubleshooting

### Common Issues

#### 1. Job Not Starting
```bash
# Check CronJob status
kubectl describe cronjob my-cronjob

# Check if CronJob is suspended
kubectl get cronjob my-cronjob -o yaml | grep suspend

# Check events
kubectl get events --field-selector involvedObject.name=my-cronjob

# Get the most recent job
kubectl get jobs -l job-name=my-cronjob --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}'

# View the status of the most recent job
kubectl describe job $(kubectl get jobs -l job-name=my-cronjob --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')

# View the pod associated with the most recent job
kubectl get pods -l job-name=$(kubectl get jobs -l job-name=my-cronjob --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}') -o wide
```

#### 2. Job Failing
```bash
# List recent jobs
kubectl get jobs -l job-name=my-cronjob

# Check job logs
kubectl logs job/my-cronjob-1234567890

# Describe failed job
kubectl describe job my-cronjob-1234567890
```

#### 3. Schedule Issues
```bash
# Verify cron expression
kubectl get cronjob my-cronjob -o jsonpath='{.spec.schedule}'

# Check last schedule time
kubectl get cronjob my-cronjob -o jsonpath='{.status.lastScheduleTime}'
```


### Debugging Commands

```bash
# List all CronJobs
kubectl get cronjobs

# Get CronJob details
kubectl describe cronjob my-cronjob

# Check CronJob history
kubectl get jobs -l job-name=my-cronjob

# View logs from latest job
kubectl logs -l job-name=my-cronjob --tail=50

# Manually trigger a job
kubectl create job my-manual-job --from=cronjob/my-cronjob

# Suspend a CronJob
kubectl patch cronjob my-cronjob -p '{"spec":{"suspend":true}}'

# Resume a CronJob
kubectl patch cronjob my-cronjob -p '{"spec":{"suspend":false}}'
```

---

## References

- [Kubernetes Official Documentation: CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)
- [Kubernetes API Reference: CronJob](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.28/#cronjob-v1-batch)
- [Cron Expression Guide](https://en.wikipedia.org/wiki/Cron)
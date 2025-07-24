# Kubernetes PersistentVolumeClaim Resource Documentation

## Table of Contents
- [Overview](#overview)
- [API Specification](#api-specification)
- [Field Reference](#field-reference)
- [PVC Lifecycle](#pvc-lifecycle)
- [Access Modes](#access-modes)
- [Storage Requests and Capacity](#storage-requests-and-capacity)
- [StorageClass Selection](#storageclass-selection)
- [Volume Expansion](#volume-expansion)
- [Status and Phases](#status-and-phases)
- [Security Aspects](#security-aspects)
- [Best Practices](#best-practices)
- [Common Use Cases](#common-use-cases)
- [Integration Patterns](#integration-patterns)
- [Monitoring and Observability](#monitoring-and-observability)
- [Backup and Recovery](#backup-and-recovery)
- [Troubleshooting](#troubleshooting)

## Overview

A **PersistentVolumeClaim (PVC)** is a request for storage by a user, similar to how a Pod requests compute resources. PVCs consume PersistentVolume resources just as Pods consume node resources.

### Key Features
- **Storage request abstraction**: Users request storage without knowing infrastructure details
- **Dynamic provisioning**: Automatic PV creation through StorageClasses
- **Binding process**: Kubernetes matches PVCs to suitable PVs
- **Lifecycle management**: Independent lifecycle from Pods that use them
- **Volume expansion**: Support for increasing storage capacity (K8s 1.24+)
- **Snapshots and cloning**: Backup and restore capabilities (K8s 1.20+)

### PVC vs PV Relationship
- **PersistentVolumeClaim (PVC)**: User's request for storage with specific requirements
- **PersistentVolume (PV)**: Actual storage resource in the cluster
- **Binding**: Controller matches PVCs to compatible PVs based on requirements

## API Specification

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: string
  namespace: string
  labels: {}
  annotations: {}
spec:
  accessModes: []                    # Required: How volume can be accessed
  resources:                         # Required: Resource requirements
    requests:
      storage: string                # Amount of storage requested
    limits:
      storage: string                # Maximum storage allowed
  volumeName: string                 # Bind to specific PV by name
  storageClassName: string           # StorageClass for dynamic provisioning
  volumeMode: string                 # Filesystem or Block
  selector:                          # Label selector for PVs
    matchLabels: {}
    matchExpressions: []
  dataSource:                        # Data source for volume creation
    name: string
    kind: string
    apiGroup: string
  dataSourceRef:                     # Enhanced data source (K8s 1.24+)
    name: string
    kind: string
    apiGroup: string
    namespace: string                # Cross-namespace data sources
status:
  phase: string                      # Current phase of PVC
  accessModes: []                    # Access modes of bound volume
  capacity:                          # Actual capacity of bound volume
    storage: string
  conditions: []                     # Detailed status conditions
  volumeName: string                 # Name of bound PV
  allocatedResources:               # Allocated storage resources
    storage: string
  resizeStatus: string              # Status of resize operation
  currentVolumeAttributesClassName: string # Current volume attributes class
  modifyVolumeStatus:               # Volume modification status
    status: string
    targetVolumeAttributesClassName: string
```

## Field Reference

### Metadata Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Name of the PVC (unique within namespace) |
| `namespace` | string | Namespace where PVC resides |
| `labels` | map[string]string | Labels for organizing and selecting PVCs |
| `annotations` | map[string]string | Additional metadata and configuration hints |

### Spec Fields

#### accessModes (Required)
**Type**: `[]string`  
**Description**: How the volume can be accessed by Pods

```yaml
spec:
  accessModes:
  - ReadWriteOnce      # Single node read-write
  - ReadOnlyMany       # Multiple nodes read-only  
  - ReadWriteMany      # Multiple nodes read-write
  - ReadWriteOncePod   # Single pod read-write (K8s 1.22+)
```

#### resources (Required)
**Type**: `ResourceRequirements`  
**Description**: Storage resource requirements

```yaml
spec:
  resources:
    requests:
      storage: "100Gi"   # Required: Amount of storage requested
    limits:
      storage: "500Gi"   # Optional: Maximum storage allowed
```

#### storageClassName
**Type**: `string`  
**Description**: StorageClass to use for dynamic provisioning

```yaml
spec:
  storageClassName: "premium-ssd"  # Use specific StorageClass
  # storageClassName: ""           # Use default StorageClass
  # storageClassName: null         # Disable dynamic provisioning
```

#### volumeMode
**Type**: `string`  
**Default**: `Filesystem`  
**Options**: `Filesystem`, `Block`

```yaml
spec:
  volumeMode: Block  # Raw block device access
```

#### selector
**Type**: `LabelSelector`  
**Description**: Label selector to bind to specific PVs

```yaml
spec:
  selector:
    matchLabels:
      environment: production
      tier: database
    matchExpressions:
    - key: zone
      operator: In
      values: ["us-east-1a", "us-east-1b"]
```

#### volumeName
**Type**: `string`  
**Description**: Bind to specific PV by name (static binding)

```yaml
spec:
  volumeName: "pv-database-01"  # Bind to specific PV
```

#### dataSource
**Type**: `TypedLocalObjectReference`  
**Description**: Create volume from existing data source

```yaml
spec:
  dataSource:
    name: "database-snapshot"
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
```

#### dataSourceRef (K8s 1.24+)
**Type**: `TypedObjectReference`  
**Description**: Enhanced data source with cross-namespace support

```yaml
spec:
  dataSourceRef:
    name: "backup-snapshot"
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
    namespace: "backup-namespace"  # Cross-namespace reference
```

## PVC Lifecycle

### PVC Phases

1. **Pending**: PVC is created but not yet bound to a PV
2. **Bound**: PVC is bound to a PV and ready for use
3. **Lost**: PV bound to PVC is lost or unavailable

### Binding Process

```yaml
# Step 1: Create PVC
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-claim
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: premium

---
# Step 2: Controller finds matching PV or creates new one
# If StorageClass exists, new PV is dynamically provisioned
# If no StorageClass, controller finds compatible existing PV

# Step 3: PVC transitions to Bound phase
# status.phase: Bound
# status.volumeName: pvc-12345678-1234-1234-1234-123456789012

---
# Step 4: Pod uses the PVC  
apiVersion: v1
kind: Pod
metadata:
  name: app-pod
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: data-claim
```

### Dynamic Provisioning Flow

```yaml
# 1. StorageClass defines provisioner
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true

---
# 2. PVC requests storage from StorageClass
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-claim
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
  storageClassName: fast-ssd

# 3. Controller automatically creates PV using CSI driver
# 4. PVC binds to newly created PV
# 5. Pod can use PVC immediately
```

## Access Modes

### ReadWriteOnce (RWO)
Most common access mode for single-node storage:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: database-claim
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
  storageClassName: premium-ssd
```

**Use Cases**: Databases, single-Pod applications, block storage

### ReadOnlyMany (ROX)
Multiple Pods can read the same data:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: config-claim
spec:
  accessModes:
  - ReadOnlyMany
  resources:
    requests:
      storage: 1Gi
  storageClassName: nfs
```

**Use Cases**: Configuration files, static content, shared libraries

### ReadWriteMany (RWX)
Multiple Pods can read and write simultaneously:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-storage-claim
spec:
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 500Gi
  storageClassName: efs
```

**Use Cases**: Shared file systems, collaborative applications, distributed workloads

### ReadWriteOncePod (RWOP) - K8s 1.22+
Exclusive access for a single Pod:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: exclusive-claim
spec:
  accessModes:
  - ReadWriteOncePod
  resources:
    requests:
      storage: 50Gi
  storageClassName: premium-ssd
```

**Use Cases**: Databases requiring exclusive access, single-writer scenarios

### Access Mode Compatibility Matrix

| Storage Type | RWO | ROX | RWX | RWOP |
|-------------|-----|-----|-----|------|
| AWS EBS | ✅ | ✅ | ❌ | ✅ |
| AWS EFS | ✅ | ✅ | ✅ | ✅ |
| Azure Disk | ✅ | ✅ | ❌ | ✅ |
| Azure Files | ✅ | ✅ | ✅ | ✅ |
| GCE PD | ✅ | ✅ | ❌ | ✅ |
| GCE Filestore | ✅ | ✅ | ✅ | ✅ |
| NFS | ✅ | ✅ | ✅ | ✅ |
| Local | ✅ | ✅ | ❌ | ✅ |

## Storage Requests and Capacity

### Storage Requests

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: sized-claim
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: "100Gi"    # Minimum storage required
    limits:
      storage: "500Gi"    # Maximum storage allowed (optional)
  storageClassName: expandable
```

### Capacity Matching

PVC binding considers capacity matching:

```yaml
# PV with 150Gi capacity
apiVersion: v1
kind: PersistentVolume
metadata:
  name: large-pv
spec:
  capacity:
    storage: 150Gi
  accessModes:
  - ReadWriteOnce

---
# PVC requesting 100Gi will bind to 150Gi PV
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: small-claim
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi  # Gets 150Gi PV (over-provisioned)
```

### Storage Units

```yaml
spec:
  resources:
    requests:
      storage: "1Gi"      # 1024^3 bytes (binary)
      # storage: "1G"     # 1000^3 bytes (decimal)
      # storage: "1Ti"    # 1024^4 bytes (terabyte)
      # storage: "1000m"  # 1 byte (milli-units)
```

## StorageClass Selection

### Default StorageClass

```yaml
# Use default StorageClass (if marked as default)
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: default-claim
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  # storageClassName omitted = use default
```

### Specific StorageClass

```yaml
# Use specific StorageClass
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: premium-claim
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: premium-ssd
```

### No Dynamic Provisioning

```yaml
# Disable dynamic provisioning (bind to existing PVs only)
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: static-claim
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: ""  # Empty string disables dynamic provisioning
```

### StorageClass Parameters

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: optimized-storage
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
  encrypted: "true"
  fsType: ext4
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Delete
mountOptions:
- noatime
- data=ordered
```

## Volume Expansion

### Enabling Volume Expansion

StorageClass must allow expansion:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: expandable-storage
provisioner: ebs.csi.aws.com
allowVolumeExpansion: true  # Enable expansion
parameters:
  type: gp3
```

### Expanding a PVC

```yaml
# Original PVC
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: expandable-claim
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
  storageClassName: expandable-storage

---
# Update PVC to request more storage
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: expandable-claim
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 200Gi  # Increased from 100Gi
  storageClassName: expandable-storage
```

### Expansion Process

```bash
# 1. Update PVC resource request
kubectl patch pvc expandable-claim -p '{"spec":{"resources":{"requests":{"storage":"200Gi"}}}}'

# 2. Check expansion status
kubectl get pvc expandable-claim -o wide

# 3. Monitor conditions
kubectl describe pvc expandable-claim

# 4. For offline expansion, restart Pod
kubectl rollout restart deployment/app-deployment
```

### Expansion Conditions

```yaml
status:
  conditions:
  - type: Resizing
    status: "True"
    message: "Waiting for user to (re-)start a Pod to finish file system resize of volume on node."
  - type: FileSystemResizePending
    status: "True" 
    message: "Waiting for user to (re-)start a Pod to finish file system resize of volume on node."
```

## Status and Phases

### PVC Status Fields

```yaml
status:
  phase: Bound                     # Current phase
  accessModes:                     # Access modes of bound volume
  - ReadWriteOnce
  capacity:                        # Actual capacity
    storage: 100Gi
  conditions:                      # Detailed conditions
  - type: Resizing
    status: "False"
    lastTransitionTime: "2025-01-01T00:00:00Z"
  volumeName: pvc-12345           # Bound PV name
  allocatedResources:             # Allocated resources
    storage: 100Gi
  resizeStatus: ""                # Resize operation status
```

### Status Conditions

```yaml
# Common conditions
conditions:
- type: Resizing
  status: "True"
  reason: "ResizeStarted"
  message: "External resizer is resizing volume"

- type: FileSystemResizePending  
  status: "True"
  reason: "FileSystemResizePending"
  message: "Waiting for user to restart Pod"

- type: VolumeResizeFailed
  status: "True" 
  reason: "ResizeFailed"
  message: "Volume resize failed: insufficient space"
```

### Monitoring PVC Status

```bash
# Check PVC phase and capacity
kubectl get pvc -o wide

# Detailed status information
kubectl describe pvc my-claim

# Watch PVC status changes
kubectl get pvc my-claim -w

# Check conditions
kubectl get pvc my-claim -o jsonpath='{.status.conditions[*]}'
```

## Security Aspects

### Pod Security Standards

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000              # File system group for volume ownership
    fsGroupChangePolicy: OnRootMismatch  # Only change ownership when needed
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: nginx
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
      runAsNonRoot: true
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: secure-claim
```

### SELinux Support (K8s 1.33+)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: selinux-pod
spec:
  securityContext:
    seLinuxOptions:
      level: "s0:c123,c456"
      type: "container_file_t"
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: data
      mountPath: /data
      seLinuxOptions:
        level: "s0:c123,c456"
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: selinux-claim
```

### RBAC for PVC Management

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pvc-manager
rules:
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["persistentvolumes"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["storage.k8s.io"]
  resources: ["storageclasses"]
  verbs: ["get", "list", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pvc-manager-binding
subjects:
- kind: ServiceAccount
  name: pvc-manager-sa
  namespace: default
roleRef:
  kind: Role
  name: pvc-manager
  apiGroup: rbac.authorization.k8s.io
```

## Best Practices

### Resource Management

```yaml
# Use ResourceQuota to control PVC usage
apiVersion: v1
kind: ResourceQuota
metadata:
  name: storage-quota
  namespace: production
spec:
  hard:
    requests.storage: "1Ti"
    persistentvolumeclaims: "50"
    count/storageclass.storage.k8s.io/premium: "10"

---
# Use LimitRange for PVC size constraints
apiVersion: v1
kind: LimitRange
metadata:
  name: pvc-limits
  namespace: production
spec:
  limits:
  - type: PersistentVolumeClaim
    min:
      storage: 1Gi
    max:
      storage: 1Ti
    default:
      storage: 10Gi
    defaultRequest:
      storage: 5Gi
```

### Naming Conventions

```yaml
# Use descriptive names with environment and purpose
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: prod-database-data-claim
  labels:
    app: database
    environment: production
    tier: data
    backup-policy: daily
  annotations:
    storage.kubernetes.io/selected-node: node-1
    volume.beta.kubernetes.io/storage-provisioner: ebs.csi.aws.com
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
  storageClassName: premium-ssd
```

### Performance Optimization

```yaml
# Use appropriate StorageClass for workload
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: high-performance-db
provisioner: ebs.csi.aws.com
parameters:
  type: io2
  iops: "10000"
  throughput: "1000"
  fsType: ext4
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
mountOptions:
- noatime
- data=writeback
```

### Cost Management

```yaml
# Use gp3 for cost-effective performance
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: cost-optimized
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"      # Baseline IOPS
  throughput: "125"  # Baseline throughput
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
```

## Common Use Cases

### Database Storage

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-data-claim
  labels:
    app: mysql
    component: database
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
  storageClassName: premium-ssd

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: root-password
        volumeMounts:
        - name: data
          mountPath: /var/lib/mysql
        resources:
          requests:
            memory: 1Gi
            cpu: 500m
          limits:
            memory: 2Gi
            cpu: 1000m
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: mysql-data-claim
```

### Shared File Storage

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-files-claim
  labels:
    type: shared-storage
spec:
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 500Gi
  storageClassName: efs

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-servers
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web-server
  template:
    metadata:
      labels:
        app: web-server
    spec:
      containers:
      - name: nginx
        image: nginx
        volumeMounts:
        - name: shared-content
          mountPath: /usr/share/nginx/html
      volumes:
      - name: shared-content
        persistentVolumeClaim:
          claimName: shared-files-claim
```

### Development Environment

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dev-workspace-claim
  labels:
    environment: development
    user: developer-1
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 50Gi
  storageClassName: standard

---
apiVersion: v1
kind: Pod
metadata:
  name: dev-environment
spec:
  containers:
  - name: dev-tools
    image: ubuntu:20.04
    command: ["sleep", "infinity"]
    volumeMounts:
    - name: workspace
      mountPath: /workspace
    resources:
      requests:
        memory: 512Mi
        cpu: 250m
  volumes:
  - name: workspace
    persistentVolumeClaim:
      claimName: dev-workspace-claim
```

## Integration Patterns

### StatefulSet Integration

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: distributed-database
spec:
  serviceName: database-headless
  replicas: 3
  selector:
    matchLabels:
      app: distributed-db
  template:
    metadata:
      labels:
        app: distributed-db
    spec:
      containers:
      - name: database
        image: cassandra:3.11
        ports:
        - containerPort: 9042
        volumeMounts:
        - name: data
          mountPath: /var/lib/cassandra
        - name: config
          mountPath: /etc/cassandra
        env:
        - name: CASSANDRA_SEEDS
          value: "distributed-database-0.database-headless"
      volumes:
      - name: config
        configMap:
          name: cassandra-config
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: premium-ssd
      resources:
        requests:
          storage: 200Gi
```

### Init Container Pattern

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data-claim
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: standard

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-with-init
spec:
  replicas: 1
  selector:
    matchLabels:
      app: initialized-app
  template:
    metadata:
      labels:
        app: initialized-app
    spec:
      initContainers:
      - name: data-initializer
        image: busybox
        command:
        - sh
        - -c
        - |
          if [ ! -f /data/initialized ]; then
            echo "Initializing data directory..."
            mkdir -p /data/config /data/logs
            echo "$(date): Initialized" > /data/initialized
          fi
        volumeMounts:
        - name: data
          mountPath: /data
      containers:
      - name: app
        image: nginx
        volumeMounts:
        - name: data
          mountPath: /usr/share/nginx/html
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: app-data-claim
```

### Sidecar Pattern

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: logs-claim
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
  storageClassName: standard

---
apiVersion: apps/v1  
kind: Deployment
metadata:
  name: app-with-sidecar
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sidecar-example
  template:
    metadata:
      labels:
        app: sidecar-example
    spec:
      containers:
      - name: app
        image: your-app:latest
        volumeMounts:
        - name: logs
          mountPath: /var/log/app
      - name: log-shipper
        image: fluent/fluentd:v1.16
        volumeMounts:
        - name: logs
          mountPath: /var/log/app
          readOnly: true
        - name: fluentd-config
          mountPath: /fluentd/etc
      volumes:
      - name: logs
        persistentVolumeClaim:
          claimName: logs-claim
      - name: fluentd-config
        configMap:
          name: fluentd-config
```

## Monitoring and Observability

### Prometheus Metrics

```yaml
# ServiceMonitor for PVC metrics
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: pvc-metrics
spec:
  selector:
    matchLabels:
      app: kube-state-metrics
  endpoints:
  - port: http-metrics
    interval: 30s
    path: /metrics
    metricRelabelings:
    - sourceLabels: [__name__]
      regex: 'kube_persistentvolumeclaim_.*'
      action: keep
```

### Custom Metrics

```yaml
# PrometheusRule for PVC alerts
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: pvc-alerts
spec:
  groups:
  - name: persistentvolumeclaim.rules
    rules:
    - alert: PVCPendingTooLong
      expr: kube_persistentvolumeclaim_status_phase{phase="Pending"} == 1
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "PVC {{ $labels.persistentvolumeclaim }} pending for too long"
        description: "PVC {{ $labels.persistentvolumeclaim }} in namespace {{ $labels.namespace }} has been pending for more than 5 minutes"

    - alert: PVCStorageUsageHigh
      expr: kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes * 100 > 85
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "PVC {{ $labels.persistentvolumeclaim }} storage usage high"
        description: "PVC {{ $labels.persistentvolumeclaim }} storage usage is {{ $value }}%"

    - alert: PVCResizeFailed
      expr: kube_persistentvolumeclaim_status_condition{condition="VolumeResizeFailed",status="true"} == 1
      for: 1m
      labels:
        severity: critical
      annotations:
        summary: "PVC {{ $labels.persistentvolumeclaim }} resize failed"
        description: "PVC {{ $labels.persistentvolumeclaim }} resize operation failed"
```

### Grafana Dashboard

```json
{
  "dashboard": {
    "title": "PVC Monitoring",
    "panels": [
      {
        "title": "PVC Status Distribution",
        "type": "piechart",
        "targets": [
          {
            "expr": "count by (phase) (kube_persistentvolumeclaim_status_phase)",
            "legendFormat": "{{ phase }}"
          }
        ]
      },
      {
        "title": "Storage Usage by PVC",
        "type": "graph",
        "targets": [
          {
            "expr": "kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes * 100",
            "legendFormat": "{{ persistentvolumeclaim }}"
          }
        ]
      },
      {
        "title": "PVC Creation Rate",
        "type": "graph", 
        "targets": [
          {
            "expr": "rate(kube_persistentvolumeclaim_created[5m])",
            "legendFormat": "PVC Creation Rate"
          }
        ]
      }
    ]
  }
}
```

## Backup and Recovery

### Volume Snapshots (K8s 1.20+)

```yaml
# VolumeSnapshotClass
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: csi-snapshotter
driver: ebs.csi.aws.com
deletionPolicy: Delete
parameters:
  tagSpecification_1: "Name={{ .VolumeSnapshotName }}"
  tagSpecification_2: "CreatedBy=kubernetes"

---
# Create snapshot of PVC
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: database-backup-snapshot
  labels:
    backup-schedule: daily
spec:
  volumeSnapshotClassName: csi-snapshotter
  source:
    persistentVolumeClaimName: mysql-data-claim

---
# Restore from snapshot
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: restored-data-claim
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
  storageClassName: premium-ssd
  dataSource:
    name: database-backup-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
```

### Cross-Namespace Restore (K8s 1.24+)

```yaml
# Restore from snapshot in different namespace
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cross-ns-restore-claim
  namespace: disaster-recovery
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
  storageClassName: premium-ssd
  dataSourceRef:
    name: production-backup-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
    namespace: production
```

### Backup Automation

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: pvc-backup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: backup-operator
          containers:
          - name: backup
            image: backup-tool:latest
            command:
            - /bin/bash
            - -c
            - |
              # Create snapshot for each PVC
              for pvc in $(kubectl get pvc -o name); do
                pvc_name=$(echo $pvc | cut -d'/' -f2)
                snapshot_name="${pvc_name}-backup-$(date +%Y%m%d-%H%M%S)"
                
                cat <<EOF | kubectl apply -f -
              apiVersion: snapshot.storage.k8s.io/v1
              kind: VolumeSnapshot
              metadata:
                name: ${snapshot_name}
                labels:
                  backup-type: automated
                  source-pvc: ${pvc_name}
              spec:
                volumeSnapshotClassName: csi-snapshotter
                source:
                  persistentVolumeClaimName: ${pvc_name}
              EOF
              done
          restartPolicy: OnFailure
```

## Troubleshooting

### Common Issues

#### 1. PVC Stuck in Pending

```bash
# Check PVC status and events
kubectl describe pvc stuck-pvc

# Common causes and solutions:
# - No matching PV available
kubectl get pv

# - StorageClass not found
kubectl get storageclass

# - Insufficient permissions
kubectl describe storageclass my-storage-class

# - CSI driver issues
kubectl get pods -n kube-system | grep csi

# - Node selector constraints
kubectl get nodes --show-labels
```

#### 2. Volume Mount Failures

```bash
# Check Pod events
kubectl describe pod failing-pod

# Check volume attachment
kubectl get volumeattachments

# Check CSI driver logs
kubectl logs -n kube-system -l app=ebs-csi-controller

# Check node CSI driver
kubectl logs -n kube-system -l app=ebs-csi-node
```

#### 3. Resize Operations Failing

```bash
# Check resize status
kubectl get pvc resizing-pvc -o wide

# Check conditions
kubectl get pvc resizing-pvc -o jsonpath='{.status.conditions[*]}'

# Check events
kubectl get events --field-selector involvedObject.name=resizing-pvc

# Manual filesystem resize (if needed)
kubectl exec -it pod-name -- resize2fs /dev/device
```

### Diagnostic Commands

```bash
# List all PVCs with detailed information
kubectl get pvc -o wide --all-namespaces

# Check PVC status and capacity
kubectl get pvc -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName,CAPACITY:.status.capacity.storage,ACCESS:.spec.accessModes,STORAGECLASS:.spec.storageClassName"

# Monitor PVC events
kubectl get events --field-selector involvedObject.kind=PersistentVolumeClaim --sort-by=.metadata.creationTimestamp

# Check storage quotas
kubectl describe quota -n namespace-name

# View PVC usage metrics (if metrics-server available)
kubectl top pvc

# Check volume snapshots
kubectl get volumesnapshots

# List failed volume operations
kubectl get events --field-selector reason=ProvisioningFailed,reason=VolumeResizeFailed
```

### Recovery Procedures

```bash
# Force delete stuck PVC
kubectl patch pvc stuck-pvc -p '{"metadata":{"finalizers":null}}'

# Manually bind PVC to PV
kubectl patch pv available-pv -p '{"spec":{"claimRef":{"name":"my-pvc","namespace":"default"}}}'

# Recreate failed PVC with same name (for StatefulSets)
kubectl delete pvc data-statefulset-0
# StatefulSet controller will recreate it automatically

# Emergency data recovery from PV
kubectl patch pv orphaned-pv -p '{"spec":{"claimRef":null}}'
# Create new PVC to bind to the PV

# Reset resize status (if stuck)
kubectl patch pvc resizing-pvc -p '{"status":{"conditions":null}}'
```

### Health Checks

```bash
# Check PVC health status
kubectl get pvc -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.status.conditions[?(@.type=="Resizing")].status}{"\n"}{end}'

# Monitor storage capacity usage
kubectl get pvc -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.capacity.storage}{"\n"}{end}'

# Check for volume health issues
kubectl get events --field-selector reason=VolumeUnhealthy

# Validate StorageClass functionality
kubectl get storageclass -o yaml | grep -A 5 -B 5 allowVolumeExpansion
```

---

## References

- [Kubernetes Official Documentation: Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Kubernetes API Reference: PersistentVolumeClaim](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.29/#persistentvolumeclaim-v1-core)
- [Volume Snapshots](https://kubernetes.io/docs/concepts/storage/volume-snapshots/)
- [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [Dynamic Volume Provisioning](https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/)
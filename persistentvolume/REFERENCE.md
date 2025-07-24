# Kubernetes PersistentVolume Resource Documentation

## Table of Contents
- [Overview](#overview)
- [API Specification](#api-specification)
- [Field Reference](#field-reference)
- [Storage Classes and Provisioning](#storage-classes-and-provisioning)
- [Access Modes](#access-modes)
- [Reclaim Policies](#reclaim-policies)
- [Volume Types](#volume-types)
- [Binding and Lifecycle](#binding-and-lifecycle)
- [Performance Considerations](#performance-considerations)
- [Security Aspects](#security-aspects)
- [Common Use Cases](#common-use-cases)
- [Best Practices](#best-practices)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

## Overview

A **PersistentVolume (PV)** is a piece of storage in the cluster that has been provisioned by an administrator or dynamically provisioned using Storage Classes. It is a resource in the cluster just like a node is a cluster resource.

### Key Features
- **Cluster-level resource**: Independent of any individual Pod
- **Storage abstraction**: Provides an API for storage consumption
- **Lifecycle management**: Manages storage from creation to deletion
- **Access control**: Supports various access modes and security contexts
- **Dynamic provisioning**: Automatic creation through StorageClasses
- **Volume expansion**: Support for expanding volumes without downtime

### PersistentVolume vs PersistentVolumeClaim
- **PersistentVolume (PV)**: Storage resource provisioned by admin/StorageClass
- **PersistentVolumeClaim (PVC)**: User request for storage with specific requirements
- **Binding**: Kubernetes matches PVCs to available PVs based on requirements

## API Specification

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: string
  labels: {}
  annotations: {}
spec:
  capacity:
    storage: string                    # Storage size (e.g., "10Gi")
  volumeMode: string                   # Filesystem or Block
  accessModes: []                      # Access patterns
  persistentVolumeReclaimPolicy: string # Retain, Delete, or Recycle
  storageClassName: string             # Storage class name
  mountOptions: []                     # Mount options
  volumeAttributes: {}                 # Volume-specific attributes
  nodeAffinity:                        # Node constraints
    required:
      nodeSelectorTerms: []
  # Volume source (one of the following):
  hostPath:
    path: string
    type: string
  nfs:
    server: string
    path: string
    readOnly: boolean
  csi:
    driver: string
    volumeHandle: string
    readOnly: boolean
    fsType: string
    volumeAttributes: {}
    nodeStageSecretRef:
      name: string
      namespace: string
    nodePublishSecretRef:
      name: string
      namespace: string
    controllerExpandSecretRef:
      name: string
      namespace: string
  # Legacy volume types (deprecated)
  awsElasticBlockStore: {}
  azureDisk: {}
  gcePersistentDisk: {}
status:
  phase: string                        # Available, Bound, Released, Failed
  message: string                      # Human-readable message
  reason: string                       # Reason for current phase
  lastPhaseTransitionTime: string      # Time of last phase change
```

## Field Reference

### Metadata Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Name of the PersistentVolume |
| `labels` | map[string]string | Labels for organizing and selecting PVs |
| `annotations` | map[string]string | Additional metadata and configuration |

### Spec Fields

#### capacity (Required)
**Type**: `ResourceList`  
**Description**: Storage capacity of the volume

```yaml
spec:
  capacity:
    storage: "100Gi"  # Size of the volume
```

#### volumeMode
**Type**: `string`  
**Default**: `Filesystem`  
**Options**: `Filesystem`, `Block`

```yaml
spec:
  volumeMode: Block  # Raw block device access
```

#### accessModes (Required)
**Type**: `[]string`  
**Description**: How the volume can be accessed

```yaml
spec:
  accessModes:
  - ReadWriteOnce      # Single node read-write
  - ReadOnlyMany       # Multiple nodes read-only
  - ReadWriteMany      # Multiple nodes read-write
  - ReadWriteOncePod   # Single pod read-write (K8s 1.22+)
```

#### persistentVolumeReclaimPolicy
**Type**: `string`  
**Default**: `Retain`  
**Options**: `Retain`, `Delete`, `Recycle` (deprecated)

```yaml
spec:
  persistentVolumeReclaimPolicy: Retain  # Keep data after PVC deletion
```

#### storageClassName
**Type**: `string`  
**Description**: Storage class for dynamic provisioning

```yaml
spec:
  storageClassName: "premium-ssd"  # Links to StorageClass
```

#### mountOptions
**Type**: `[]string`  
**Description**: Additional mount options

```yaml
spec:
  mountOptions:
  - hard
  - nfsvers=4.1
  - rsize=1048576
```

#### nodeAffinity
**Type**: `VolumeNodeAffinity`  
**Description**: Node constraints for volume attachment

```yaml
spec:
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values: ["node1", "node2"]
```

## Storage Classes and Provisioning

### Static Provisioning

Administrator pre-provisions PersistentVolumes:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: static-pv-example
spec:
  capacity:
    storage: 10Gi
  volumeMode: Filesystem
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /mnt/data
    type: DirectoryOrCreate
```

### Dynamic Provisioning

StorageClass automatically creates PVs:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: premium-ssd
provisioner: kubernetes.io/aws-ebs  # CSI driver
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Delete
```

### CSI Drivers (2025 Recommended)

Modern storage uses CSI (Container Storage Interface):

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: aws-ebs-csi
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

**Popular CSI Drivers (2025)**:
- **AWS**: `ebs.csi.aws.com`, `efs.csi.aws.com`
- **Azure**: `disk.csi.azure.com`, `file.csi.azure.com`
- **GCP**: `pd.csi.storage.gke.io`, `filestore.csi.storage.gke.io`
- **VMware**: `csi.vsphere.vmware.com`
- **NetApp**: `csi.trident.netapp.io`

## Access Modes

### ReadWriteOnce (RWO)
Volume can be mounted as read-write by a single node:

```yaml
spec:
  accessModes:
  - ReadWriteOnce
  # Use case: Database storage, single-node applications
```

### ReadOnlyMany (ROX)
Volume can be mounted as read-only by many nodes:

```yaml
spec:
  accessModes:
  - ReadOnlyMany
  # Use case: Configuration files, static content
```

### ReadWriteMany (RWX)
Volume can be mounted as read-write by many nodes:

```yaml
spec:
  accessModes:
  - ReadWriteMany
  # Use case: Shared file systems, collaborative workloads
```

### ReadWriteOncePod (RWOP)
Volume can be mounted as read-write by a single Pod (K8s 1.22+):

```yaml
spec:
  accessModes:
  - ReadWriteOncePod
  # Use case: Databases requiring exclusive access
```

**Access Mode Support by Volume Type**:

| Volume Type | RWO | ROX | RWX | RWOP |
|-------------|-----|-----|-----|------|
| AWS EBS | ✅ | ✅ | ❌ | ✅ |
| AWS EFS | ✅ | ✅ | ✅ | ✅ |
| Azure Disk | ✅ | ✅ | ❌ | ✅ |
| Azure File | ✅ | ✅ | ✅ | ✅ |
| GCE PD | ✅ | ✅ | ❌ | ✅ |
| NFS | ✅ | ✅ | ✅ | ✅ |
| HostPath | ✅ | ✅ | ✅ | ✅ |

## Reclaim Policies

### Retain
Volume is kept after PVC deletion:

```yaml
spec:
  persistentVolumeReclaimPolicy: Retain
```

**Characteristics**:
- Manual cleanup required
- Data preserved for recovery
- PV status becomes "Released"
- Requires manual reclaim or recreation

### Delete
Volume is deleted when PVC is deleted:

```yaml
spec:
  persistentVolumeReclaimPolicy: Delete
```

**Characteristics**:
- Automatic cleanup
- Data permanently lost
- Cloud resources deleted
- Default for dynamically provisioned volumes

### Recycle (Deprecated)
Volume is scrubbed and made available again:

```yaml
# DEPRECATED - Do not use
spec:
  persistentVolumeReclaimPolicy: Recycle
```

## Volume Types

### CSI Volumes (Recommended)

Modern CSI-based storage:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: csi-pv
spec:
  capacity:
    storage: 100Gi
  accessModes:
  - ReadWriteOnce
  csi:
    driver: ebs.csi.aws.com
    volumeHandle: vol-1234567890abcdef0
    fsType: ext4
    volumeAttributes:
      storage.kubernetes.io/csiProvisionerIdentity: "1234567890"
```

### NFS

Network File System for shared storage:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-pv
spec:
  capacity:
    storage: 50Gi
  accessModes:
  - ReadWriteMany
  nfs:
    server: nfs-server.example.com
    path: /exported/path
    readOnly: false
  mountOptions:
  - hard
  - nfsvers=4.1
```

### HostPath

Local node storage (development only):

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: hostpath-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
  - ReadWriteOnce
  hostPath:
    path: /mnt/data
    type: DirectoryOrCreate
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values: ["specific-node"]
```

### Local Volumes

High-performance local storage:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv
spec:
  capacity:
    storage: 100Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Delete
  storageClassName: local-storage
  local:
    path: /mnt/disks/ssd1
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values: ["node-1"]
```

## Binding and Lifecycle

### PV Lifecycle Phases

1. **Available**: Available for binding
2. **Bound**: Bound to a PVC
3. **Released**: PVC deleted, but not yet reclaimed
4. **Failed**: Automatic reclamation failed

### Binding Process

```yaml
# Step 1: PersistentVolume created
apiVersion: v1
kind: PersistentVolume
metadata:
  name: example-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
  - ReadWriteOnce
  hostPath:
    path: /data

---
# Step 2: PersistentVolumeClaim requests storage
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: example-pvc
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi  # Can be smaller than PV

---
# Step 3: Pod uses the PVC
apiVersion: v1
kind: Pod
metadata:
  name: example-pod
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: storage
      mountPath: /usr/share/nginx/html
  volumes:
  - name: storage
    persistentVolumeClaim:
      claimName: example-pvc
```

### Volume Expansion

Enable volume expansion in StorageClass:

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

Expand PVC:

```yaml
# Update PVC to request more storage
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: expandable-pvc
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi  # Increased from 10Gi
  storageClassName: expandable-storage
```

## Performance Considerations

### 2025 Performance Features

#### CSI Volume Health Monitoring
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: health-monitored
provisioner: ebs.csi.aws.com
parameters:
  csi.storage.k8s.io/health-monitor-enabled: "true"
```

#### Volume Performance Classes
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: high-performance
provisioner: ebs.csi.aws.com
parameters:
  type: io2
  iops: "10000"
  throughput: "1000"
volumeBindingMode: Immediate
```

### Topology-Aware Provisioning

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: topology-aware
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer  # Wait for Pod scheduling
allowedTopologies:
- matchLabelExpressions:
  - key: failure-domain.beta.kubernetes.io/zone
    values: ["us-east-1a", "us-east-1b"]
```

### Performance Optimization

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: optimized-pv
spec:
  capacity:
    storage: 100Gi
  accessModes:
  - ReadWriteOnce
  csi:
    driver: ebs.csi.aws.com
    volumeHandle: vol-optimized
    fsType: ext4
  mountOptions:
  - noatime      # Disable access time updates
  - data=writeback  # Async writes for better performance
```

## Security Aspects

### Security Contexts

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
    fsGroup: 2000  # Group for volume ownership
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
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: secure-pvc
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
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: selinux-pvc
```

### Node Constraints and Security

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: secure-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
  - ReadWriteOnce
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: node.kubernetes.io/security-zone
          operator: In
          values: ["high-security"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
  hostPath:
    path: /secure-storage
    type: Directory
```

## Common Use Cases

### Database Storage

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mysql-pv
  labels:
    type: database
spec:
  capacity:
    storage: 50Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  csi:
    driver: ebs.csi.aws.com
    volumeHandle: vol-mysql-data
    fsType: ext4
  mountOptions:
  - noatime
  - data=ordered
```

### Shared File Storage

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: shared-files-pv
spec:
  capacity:
    storage: 100Gi
  accessModes:
  - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  nfs:
    server: shared-storage.example.com
    path: /shared
  mountOptions:
  - hard
  - nfsvers=4.1
  - rsize=1048576
  - wsize=1048576
```

### StatefulSet Storage

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: statefulset-storage
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Retain

---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web-server
spec:
  serviceName: web
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    spec:
      containers:
      - name: web
        image: nginx
        volumeMounts:
        - name: data
          mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: statefulset-storage
      resources:
        requests:
          storage: 10Gi
```

### Backup and Restore

```yaml
# Volume Snapshot for backups (K8s 1.20+)
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: backup-snapshot
spec:
  volumeSnapshotClassName: csi-snapshotter
  source:
    persistentVolumeClaimName: important-data-pvc

---
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: csi-snapshotter
driver: ebs.csi.aws.com
deletionPolicy: Delete
```

## Best Practices

### Capacity Planning

```yaml
# Use resource quotas to control storage usage
apiVersion: v1
kind: ResourceQuota
metadata:
  name: storage-quota
  namespace: production
spec:
  hard:
    requests.storage: "1Ti"
    persistentvolumeclaims: "10"
    count/storageclass.storage.k8s.io/premium: "5"
```

### Monitoring and Alerting

```yaml
# ServiceMonitor for Prometheus (if using CSI with metrics)
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: csi-metrics
spec:
  selector:
    matchLabels:
      app: csi-driver
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
```

### Cost Optimization

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: cost-optimized
provisioner: ebs.csi.aws.com
parameters:
  type: gp3          # More cost-effective than gp2
  iops: "3000"       # Baseline performance
  throughput: "125"  # Baseline throughput
volumeBindingMode: WaitForFirstConsumer  # Avoid cross-AZ charges
reclaimPolicy: Delete  # Clean up unused volumes
```

### High Availability

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ha-storage
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
allowedTopologies:
- matchLabelExpressions:
  - key: topology.ebs.csi.aws.com/zone
    values: ["us-east-1a", "us-east-1b", "us-east-1c"]
volumeBindingMode: WaitForFirstConsumer
```

## Troubleshooting

### Common Issues

#### 1. PVC Stuck in Pending

```bash
# Check PVC status
kubectl get pvc -o wide

# Check PVC events
kubectl describe pvc my-pvc

# Check StorageClass
kubectl get storageclass

# Check available PVs
kubectl get pv
```

#### 2. Volume Mount Failures

```bash
# Check Pod events
kubectl describe pod my-pod

# Check node conditions
kubectl describe node <node-name>

# Check CSI driver pods
kubectl get pods -n kube-system | grep csi
```

#### 3. Performance Issues

```bash
# Check volume metrics
kubectl top pv

# Check I/O statistics
kubectl exec -it <pod> -- iostat -x 1

# Check mount options
kubectl describe pv <pv-name> | grep "Mount Options"
```

### Debugging Commands

```bash
# List all PVs
kubectl get pv
kubectl get pv -o wide

# Get PV details
kubectl describe pv <pv-name>

# Check PV status
kubectl get pv <pv-name> -o yaml

# List PVCs
kubectl get pvc
kubectl get pvc -o wide

# Check StorageClasses
kubectl get storageclass
kubectl describe storageclass <sc-name>

# Volume snapshots
kubectl get volumesnapshots
kubectl describe volumesnapshot <snapshot-name>

# CSI drivers
kubectl get csidrivers
kubectl describe csidriver <driver-name>

# Storage capacity
kubectl get csinodes
kubectl describe csinode <node-name>

# Volume attachments
kubectl get volumeattachments
kubectl describe volumeattachment <attachment-name>
```

### Health Monitoring

```bash
# Check volume health (if CSI health monitoring enabled)
kubectl get events --field-selector reason=VolumeUnhealthy

# Monitor storage usage
kubectl get pvc -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName,CAPACITY:.status.capacity.storage,STORAGECLASS:.spec.storageClassName"

# Check for expansion issues
kubectl get events --field-selector reason=VolumeResizeFailed
```

### Recovery Procedures

```bash
# Manual PV reclaim
kubectl patch pv <pv-name> -p '{"spec":{"claimRef": null}}'

# Force delete stuck PVC
kubectl patch pvc <pvc-name> -p '{"metadata":{"finalizers":null}}'

# Recreate failed volume attachment
kubectl delete volumeattachment <attachment-name>

# Check and restart CSI driver
kubectl rollout restart daemonset <csi-driver> -n kube-system
```

---

## References

- [Kubernetes Official Documentation: Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Kubernetes API Reference: PersistentVolume](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.29/#persistentvolume-v1-core)
- [Container Storage Interface (CSI) Documentation](https://kubernetes-csi.github.io/docs/)
- [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [Volume Snapshots](https://kubernetes.io/docs/concepts/storage/volume-snapshots/)
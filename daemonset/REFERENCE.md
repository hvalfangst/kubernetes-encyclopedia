# Kubernetes DaemonSet Resource Documentation

## Table of Contents
- [Overview](#overview)
- [API Specification](#api-specification)
- [Field Reference](#field-reference)
- [Pod Template Configuration](#pod-template-configuration)
- [Common Use Cases](#common-use-cases)
- [Best Practices](#best-practices)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

## Overview

A **DaemonSet** ensures that all (or some) nodes run a copy of a pod. As nodes are added to the cluster, pods are added to them. As nodes are removed from the cluster, those pods are garbage collected. Deleting a DaemonSet will clean up the pods it created.

### Key Features
- One pod per node (or selected nodes)
- Automatic pod scheduling and management
- Node addition/removal handling
- Support for node selection and affinity
- Rolling updates and rollback capabilities
- Monitoring and logging integration

### When to Use DaemonSets
- **System daemons**: Node monitoring agents, log collection
- **Storage daemons**: Distributed storage systems like Ceph, GlusterFS
- **Network daemons**: Network plugins, load balancers, ingress controllers
- **Security agents**: Security monitoring, vulnerability scanners
- **Cluster utilities**: DNS, metrics collection, cluster networking

## API Specification

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: string
  namespace: string
  labels: {}
  annotations: {}
spec:
  selector:                           # Required: Label selector for pods
    matchLabels: {}
  template:                           # Required: Pod template
    metadata:
      labels: {}
    spec: {}
  updateStrategy:                     # Optional: Update strategy
    type: string                      # RollingUpdate or OnDelete
    rollingUpdate:
      maxUnavailable: string/integer
  minReadySeconds: integer            # Optional: Min seconds for pod to be ready
  revisionHistoryLimit: integer       # Optional: Number of old ReplicaSets to retain
status:
  currentNumberScheduled: integer     # Number of nodes running at least one pod
  numberMisscheduled: integer         # Number of nodes running pods but shouldn't
  desiredNumberScheduled: integer     # Number of nodes that should run pods
  numberReady: integer                # Number of nodes with ready pods
  numberUnavailable: integer          # Number of nodes with unavailable pods
  numberAvailable: integer            # Number of nodes with available pods
```

## Field Reference

### Metadata Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Name of the DaemonSet resource |
| `namespace` | string | Namespace where the DaemonSet resides |
| `labels` | map[string]string | Key-value pairs for organizing resources |
| `annotations` | map[string]string | Additional metadata for the resource |

### Spec Fields

#### selector (Required)
**Type**: `LabelSelector`  
**Description**: Label selector to identify pods managed by this DaemonSet

```yaml
selector:
  matchLabels:
    app: log-collector
    component: fluent-bit
```

#### template (Required)
**Type**: `PodTemplateSpec`  
**Description**: Template for pods that will be created on each node

```yaml
template:
  metadata:
    labels:
      app: log-collector
      component: fluent-bit
  spec:
    containers:
    - name: fluent-bit
      image: fluent/fluent-bit:latest
      volumeMounts:
      - name: varlog
        mountPath: /var/log
      - name: varlibdockercontainers
        mountPath: /var/lib/docker/containers
        readOnly: true
    volumes:
    - name: varlog
      hostPath:
        path: /var/log
    - name: varlibdockercontainers
      hostPath:
        path: /var/lib/docker/containers
```

### updateStrategy

**Type**: `DaemonSetUpdateStrategy`  
**Default**: `RollingUpdate`  
**Options**: `RollingUpdate`, `OnDelete`

Controls how pod updates are performed across nodes.

#### Use Cases & Examples:

**`RollingUpdate` (Default)**
- **Use Case**: Automated updates with controlled rollout
- **Example**: Log agents, monitoring tools that can tolerate brief downtime
- **Scenario**: Update pods gradually across nodes

```yaml
# Example: Rolling update for monitoring agent
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-monitor
spec:
  selector:
    matchLabels:
      app: node-monitor
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1  # Update one node at a time
  template:
    metadata:
      labels:
        app: node-monitor
    spec:
      containers:
      - name: monitor
        image: prometheus/node-exporter:latest
        ports:
        - containerPort: 9100
          hostPort: 9100
```

**`OnDelete`**
- **Use Case**: Manual control over updates, critical system components
- **Example**: Network plugins, storage daemons that require careful coordination
- **Scenario**: Update pods only when manually deleted

```yaml
# Example: Network plugin requiring manual update control
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: network-plugin
spec:
  selector:
    matchLabels:
      app: network-plugin
  updateStrategy:
    type: OnDelete  # Manual updates only
  template:
    metadata:
      labels:
        app: network-plugin
    spec:
      hostNetwork: true
      containers:
      - name: network-daemon
        image: network-plugin:v1.2.3
        securityContext:
          privileged: true
```

---

### maxUnavailable

**Type**: `string/integer`  
**Default**: `1`  
**Description**: Maximum number of pods that can be unavailable during rolling update

#### Use Cases & Examples:

**Low Values (1 or 25%)**:
- **Use Case**: Critical services requiring high availability
- **Example**: DNS services, network components
- **Scenario**: Minimize service disruption during updates

```yaml
# Example: DNS service with minimal disruption
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: dns-cache
spec:
  selector:
    matchLabels:
      app: dns-cache
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1  # Update one node at a time
  template:
    metadata:
      labels:
        app: dns-cache
    spec:
      hostNetwork: true
      containers:
      - name: dns-cache
        image: k8s.gcr.io/dns/k8s-dns-node-cache:1.21.1
        ports:
        - containerPort: 53
          protocol: UDP
```

**Higher Values (50% or more)**:
- **Use Case**: Non-critical services, development environments
- **Example**: Log collectors, metrics exporters
- **Scenario**: Faster updates acceptable with temporary service gaps

```yaml
# Example: Log collector allowing faster updates
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-collector
spec:
  selector:
    matchLabels:
      app: log-collector
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 50%  # Update half the nodes simultaneously
  template:
    metadata:
      labels:
        app: log-collector
    spec:
      containers:
      - name: fluentd
        image: fluentd:v1.14-debian-1
        volumeMounts:
        - name: varlog
          mountPath: /var/log
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
```

---

### minReadySeconds

**Type**: `integer`  
**Default**: `0`  
**Description**: Minimum seconds for a pod to be considered ready after creation

#### Use Cases & Examples:

**Short Values (10-30 seconds)**:
- **Use Case**: Fast-starting services, simple agents
- **Example**: Metrics exporters, simple log forwarders
- **Scenario**: Quick verification that service is running

```yaml
# Example: Fast-starting metrics exporter
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: metrics-exporter
spec:
  selector:
    matchLabels:
      app: metrics-exporter
  minReadySeconds: 15  # Wait 15 seconds before considering ready
  template:
    metadata:
      labels:
        app: metrics-exporter
    spec:
      containers:
      - name: exporter
        image: prom/node-exporter:latest
        readinessProbe:
          httpGet:
            path: /metrics
            port: 9100
          initialDelaySeconds: 5
          periodSeconds: 10
```

**Longer Values (60+ seconds)**:
- **Use Case**: Complex services requiring initialization time
- **Example**: Storage daemons, network plugins with warm-up periods
- **Scenario**: Services need time to establish connections, load data

```yaml
# Example: Storage daemon requiring initialization time
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: storage-daemon
spec:
  selector:
    matchLabels:
      app: storage-daemon
  minReadySeconds: 120  # Wait 2 minutes for full initialization
  template:
    metadata:
      labels:
        app: storage-daemon
    spec:
      containers:
      - name: storage
        image: ceph/daemon:latest
        readinessProbe:
          exec:
            command:
            - /health-check.sh
          initialDelaySeconds: 30
          periodSeconds: 10
        volumeMounts:
        - name: storage-config
          mountPath: /etc/ceph
      volumes:
      - name: storage-config
        configMap:
          name: ceph-config
```

---

### revisionHistoryLimit

**Type**: `integer`  
**Default**: `10`  
**Description**: Number of old ReplicaSets to retain for rollback purposes

#### Use Cases & Examples:

**Low Values (1-3)**:
- **Use Case**: Production environments with limited storage
- **Example**: Large clusters with many DaemonSets
- **Scenario**: Minimize etcd storage usage

```yaml
# Example: Production DaemonSet with minimal history
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: production-agent
spec:
  revisionHistoryLimit: 2  # Keep only 2 previous versions
  selector:
    matchLabels:
      app: production-agent
  template:
    metadata:
      labels:
        app: production-agent
    spec:
      containers:
      - name: agent
        image: production-agent:v2.1.0
```

**Higher Values (5-10)**:
- **Use Case**: Development/staging environments requiring rollback flexibility
- **Example**: Experimental features, frequent updates
- **Scenario**: Need multiple rollback options for testing

```yaml
# Example: Development DaemonSet with extended history
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: dev-monitor
spec:
  revisionHistoryLimit: 8  # Keep 8 versions for rollback flexibility
  selector:
    matchLabels:
      app: dev-monitor
  template:
    metadata:
      labels:
        app: dev-monitor
    spec:
      containers:
      - name: monitor
        image: dev-monitor:latest
```

---

## Pod Template Configuration

### Host Network Access

```yaml
template:
  spec:
    hostNetwork: true    # Use host networking
    hostPID: true        # Access host process namespace
    hostIPC: true        # Access host IPC namespace
    containers:
    - name: system-monitor
      image: system-monitor:latest
      securityContext:
        privileged: true
```

### Host Path Volumes

```yaml
template:
  spec:
    containers:
    - name: log-collector
      volumeMounts:
      - name: host-logs
        mountPath: /host/var/log
      - name: docker-socket
        mountPath: /var/run/docker.sock
    volumes:
    - name: host-logs
      hostPath:
        path: /var/log
        type: Directory
    - name: docker-socket
      hostPath:
        path: /var/run/docker.sock
        type: Socket
```

### Node Selection

```yaml
template:
  spec:
    nodeSelector:
      kubernetes.io/os: linux
      node-type: worker
    tolerations:
    - key: node-role.kubernetes.io/master
      operator: Exists
      effect: NoSchedule
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: hardware-type
              operator: In
              values:
              - ssd
              - gpu
```

## Common Use Cases

### 1. Log Collection

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluent-bit
  namespace: logging
spec:
  selector:
    matchLabels:
      app: fluent-bit
  template:
    metadata:
      labels:
        app: fluent-bit
    spec:
      serviceAccountName: fluent-bit
      containers:
      - name: fluent-bit
        image: fluent/fluent-bit:1.9.3
        ports:
        - containerPort: 2020
        volumeMounts:
        - name: varlog
          mountPath: /var/log
          readOnly: true
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
        - name: fluent-bit-config
          mountPath: /fluent-bit/etc/
      volumes:
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
      - name: fluent-bit-config
        configMap:
          name: fluent-bit-config
```

### 2. Node Monitoring

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    metadata:
      labels:
        app: node-exporter
    spec:
      hostNetwork: true
      hostPID: true
      containers:
      - name: node-exporter
        image: prom/node-exporter:v1.3.1
        ports:
        - containerPort: 9100
          hostPort: 9100
        args:
        - '--path.sysfs=/host/sys'
        - '--path.rootfs=/host/root'
        - '--no-collector.wifi'
        - '--collector.filesystem.ignored-mount-points=^/(dev|proc|sys|var/lib/docker/.+)($|/)'
        volumeMounts:
        - name: sys
          mountPath: /host/sys
          readOnly: true
        - name: root
          mountPath: /host/root
          mountPropagation: HostToContainer
          readOnly: true
      volumes:
      - name: sys
        hostPath:
          path: /sys
      - name: root
        hostPath:
          path: /
```

### 3. Network Plugin

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: kube-proxy
  namespace: kube-system
spec:
  selector:
    matchLabels:
      k8s-app: kube-proxy
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  template:
    metadata:
      labels:
        k8s-app: kube-proxy
    spec:
      hostNetwork: true
      serviceAccountName: kube-proxy
      containers:
      - name: kube-proxy
        image: k8s.gcr.io/kube-proxy:v1.24.0
        command:
        - /usr/local/bin/kube-proxy
        - --config=/var/lib/kube-proxy/config.conf
        - --hostname-override=$(NODE_NAME)
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        securityContext:
          privileged: true
        volumeMounts:
        - mountPath: /var/lib/kube-proxy
          name: kube-proxy
        - mountPath: /run/xtables.lock
          name: xtables-lock
        - mountPath: /lib/modules
          name: lib-modules
          readOnly: true
      volumes:
      - name: kube-proxy
        configMap:
          name: kube-proxy
      - name: xtables-lock
        hostPath:
          path: /run/xtables.lock
          type: FileOrCreate
      - name: lib-modules
        hostPath:
          path: /lib/modules
```

### 4. Security Agent

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: security-agent
  namespace: security
spec:
  selector:
    matchLabels:
      app: security-agent
  template:
    metadata:
      labels:
        app: security-agent
    spec:
      hostNetwork: true
      hostPID: true
      containers:
      - name: security-agent
        image: security-agent:v2.1.0
        securityContext:
          privileged: true
          readOnlyRootFilesystem: true
        env:
        - name: HOST_ROOT
          value: /host
        volumeMounts:
        - name: host-root
          mountPath: /host
          readOnly: true
        - name: host-proc
          mountPath: /host/proc
          readOnly: true
        - name: host-sys
          mountPath: /host/sys
          readOnly: true
        resources:
          limits:
            memory: 512Mi
            cpu: 200m
          requests:
            memory: 256Mi
            cpu: 100m
      volumes:
      - name: host-root
        hostPath:
          path: /
      - name: host-proc
        hostPath:
          path: /proc
      - name: host-sys
        hostPath:
          path: /sys
      tolerations:
      - operator: Exists
        effect: NoSchedule
```

## Best Practices

### 1. Resource Management
```yaml
containers:
- name: daemon
  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi"
      cpu: "200m"
```

### 2. Health Checks
```yaml
containers:
- name: daemon
  livenessProbe:
    httpGet:
      path: /health
      port: 8080
    initialDelaySeconds: 30
    periodSeconds: 10
  readinessProbe:
    httpGet:
      path: /ready
      port: 8080
    initialDelaySeconds: 5
    periodSeconds: 5
```

### 3. Security Context
```yaml
containers:
- name: daemon
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    readOnlyRootFilesystem: true
    allowPrivilegeEscalation: false
    capabilities:
      drop:
      - ALL
      add:
      - NET_BIND_SERVICE
```

### 4. Tolerations for System Pods
```yaml
tolerations:
- operator: Exists
  effect: NoSchedule
- operator: Exists
  effect: NoExecute
- key: CriticalAddonsOnly
  operator: Exists
```

## Troubleshooting

### Common Issues

#### 1. Pod Not Scheduled on All Nodes
```bash
# Check DaemonSet status
kubectl get daemonset my-daemonset -o wide

# Check node taints and tolerations
kubectl describe nodes | grep -A 5 -B 5 Taints

# Check node selector constraints
kubectl get nodes --show-labels

# Check pod events
kubectl describe pod my-pod-xyz
```

#### 2. Rolling Update Stuck
```bash
# Check rollout status
kubectl rollout status daemonset/my-daemonset

# Check update strategy
kubectl get daemonset my-daemonset -o yaml | grep -A 10 updateStrategy

# Check pod readiness
kubectl get pods -l app=my-app -o wide

# Check events
kubectl get events --sort-by=.metadata.creationTimestamp
```

#### 3. Pods Failing to Start
```bash
# Check pod logs
kubectl logs daemonset/my-daemonset

# Check pod description
kubectl describe pods -l app=my-app

# Check resource constraints
kubectl top nodes
kubectl describe nodes
```

### Debugging Commands

```bash
# List all DaemonSets
kubectl get daemonsets --all-namespaces

# Get detailed DaemonSet information
kubectl describe daemonset my-daemonset

# Check DaemonSet pods across nodes
kubectl get pods -o wide -l app=my-app

# View DaemonSet yaml
kubectl get daemonset my-daemonset -o yaml

# Check rollout history
kubectl rollout history daemonset/my-daemonset

# Rollback to previous version
kubectl rollout undo daemonset/my-daemonset

# Force restart DaemonSet pods
kubectl rollout restart daemonset/my-daemonset

# Scale down/up (pause/resume)
kubectl patch daemonset my-daemonset -p '{"spec":{"template":{"spec":{"nodeSelector":{"non-existing":"true"}}}}}'
kubectl patch daemonset my-daemonset -p '{"spec":{"template":{"spec":{"nodeSelector":null}}}}'
```

---

## References

- [Kubernetes Official Documentation: DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)
- [Kubernetes API Reference: DaemonSet](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.28/#daemonset-v1-apps)
- [DaemonSet Best Practices](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/#writing-a-daemonset-spec)
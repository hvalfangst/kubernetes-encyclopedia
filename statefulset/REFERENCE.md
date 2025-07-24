# Kubernetes StatefulSet Resource Documentation

## Table of Contents
- [Overview](#overview)
- [API Specification](#api-specification)
- [Field Reference](#field-reference)
- [StatefulSet vs Deployment](#statefulset-vs-deployment)
- [Persistent Storage](#persistent-storage)
- [Network Identity](#network-identity)
- [Update Strategies](#update-strategies)
- [Common Use Cases](#common-use-cases)
- [Best Practices](#best-practices)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

## Overview

A **StatefulSet** manages stateful applications with persistent storage and stable network identities, providing ordered, predictable deployment and scaling of Pods.

### Key Features
- Stable, unique network identifiers
- Stable, persistent storage
- Ordered, graceful deployment and scaling
- Ordered, automated rolling updates
- Guaranteed Pod ordering and uniqueness
- Persistent volumes that survive Pod rescheduling

### When to Use StatefulSets
- **Databases**: MySQL, PostgreSQL, MongoDB clusters
- **Distributed systems**: Apache Kafka, Apache ZooKeeper
- **Caching systems**: Redis clusters, Memcached
- **Message queues**: RabbitMQ clusters
- **Search engines**: Elasticsearch clusters
- **Any application requiring stable network identity or storage**

## API Specification

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: string
  namespace: string
  labels: {}
  annotations: {}
spec:
  serviceName: string                  # Required: Headless service name
  replicas: integer                    # Number of desired replicas (default: 1)
  selector:                           # Required: Pod selector
    matchLabels: {}
  template:                           # Required: Pod template
    metadata:
      labels: {}
    spec: {}
  volumeClaimTemplates: []            # Persistent volume templates
  updateStrategy:                     # Update strategy
    type: string                      # RollingUpdate or OnDelete
    rollingUpdate:
      partition: integer              # Partition for staged updates
      maxUnavailable: string/integer  # Max unavailable during update
  podManagementPolicy: string         # OrderedReady or Parallel
  revisionHistoryLimit: integer       # Number of old ReplicaSets to retain
  minReadySeconds: integer            # Min seconds for Pod to be ready
  persistentVolumeClaimRetentionPolicy: # PVC retention policy
    whenDeleted: string               # Retain or Delete
    whenScaled: string                # Retain or Delete
status:
  observedGeneration: integer         # Generation observed by controller
  replicas: integer                   # Number of replicas
  readyReplicas: integer             # Number of ready replicas
  currentReplicas: integer           # Number of current replicas
  updatedReplicas: integer           # Number of updated replicas
  currentRevision: string            # Current revision
  updateRevision: string             # Update revision
  collisionCount: integer            # Hash collision count
  conditions: []                     # StatefulSet conditions
```

## Field Reference

### Metadata Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Name of the StatefulSet resource |
| `namespace` | string | Namespace where the StatefulSet resides |
| `labels` | map[string]string | Key-value pairs for organizing resources |
| `annotations` | map[string]string | Additional metadata for the resource |

### Spec Fields

#### serviceName (Required)
**Type**: `string`  
**Description**: Name of the headless service that controls the domain

```yaml
spec:
  serviceName: "mysql-headless"  # Must exist before StatefulSet
```

#### replicas
**Type**: `integer`  
**Default**: `1`  
**Description**: Number of desired Pod replicas

```yaml
spec:
  replicas: 3  # Creates pods: mysql-0, mysql-1, mysql-2
```

#### volumeClaimTemplates
**Type**: `[]PersistentVolumeClaim`  
**Description**: Templates for creating persistent volumes

```yaml
spec:
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: "ssd"
      resources:
        requests:
          storage: 10Gi
```

#### updateStrategy
**Type**: `StatefulSetUpdateStrategy`  
**Description**: Strategy for updating Pods

**RollingUpdate (Default)**:
```yaml
spec:
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 0  # Update all pods
      maxUnavailable: 1
```

**OnDelete**:
```yaml
spec:
  updateStrategy:
    type: OnDelete  # Manual Pod deletion required for updates
```

#### podManagementPolicy
**Type**: `string`  
**Default**: `OrderedReady`  
**Options**: `OrderedReady`, `Parallel`

**OrderedReady**: Pods created/deleted in order (0, 1, 2...)
**Parallel**: Pods created/deleted simultaneously

```yaml
spec:
  podManagementPolicy: Parallel  # Faster startup
```

#### persistentVolumeClaimRetentionPolicy
**Type**: `StatefulSetPersistentVolumeClaimRetentionPolicy`  
**Description**: PVC retention when StatefulSet is deleted or scaled

```yaml
spec:
  persistentVolumeClaimRetentionPolicy:
    whenDeleted: Retain    # Keep PVCs when StatefulSet deleted
    whenScaled: Delete     # Delete PVCs when scaling down
```

## StatefulSet vs Deployment

| Feature | StatefulSet | Deployment |
|---------|-------------|------------|
| **Pod Identity** | Stable, unique (mysql-0, mysql-1) | Random (mysql-abc123, mysql-def456) |
| **Storage** | Persistent, per-Pod volumes | Shared or ephemeral storage |
| **Network** | Stable hostnames | Dynamic IP addresses |
| **Scaling** | Ordered (0→1→2) | Parallel |
| **Updates** | Ordered rolling updates | Parallel rolling updates |
| **Use Case** | Stateful applications | Stateless applications |

## Persistent Storage

### Volume Claim Templates

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: mysql-headless
  replicas: 3
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
        volumeMounts:
        - name: data
          mountPath: /var/lib/mysql
        - name: config
          mountPath: /etc/mysql/conf.d
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: root-password
      volumes:
      - name: config
        configMap:
          name: mysql-config
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: "fast-ssd"
      resources:
        requests:
          storage: 20Gi
```

### PVC Lifecycle

```yaml
# PVCs created automatically:
# mysql-data-mysql-0 (20Gi)
# mysql-data-mysql-1 (20Gi) 
# mysql-data-mysql-2 (20Gi)

# PVC retention policy
spec:
  persistentVolumeClaimRetentionPolicy:
    whenDeleted: Retain    # Keep data when StatefulSet deleted
    whenScaled: Delete     # Clean up when scaling down
```

## Network Identity

### Headless Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql-headless
  labels:
    app: mysql
spec:
  clusterIP: None  # Headless service
  selector:
    app: mysql
  ports:
  - port: 3306
    name: mysql
---
# Regular service for client access
apiVersion: v1
kind: Service
metadata:
  name: mysql
  labels:
    app: mysql
spec:
  selector:
    app: mysql
  ports:
  - port: 3306
    name: mysql
```

### DNS Names

```yaml
# Each Pod gets stable DNS name:
# mysql-0.mysql-headless.default.svc.cluster.local
# mysql-1.mysql-headless.default.svc.cluster.local
# mysql-2.mysql-headless.default.svc.cluster.local

# Usage in applications:
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: client
    image: mysql:8.0
    command: ['mysql', '-h', 'mysql-0.mysql-headless', '-u', 'root', '-p']
```

## Update Strategies

### Rolling Update

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web-server
spec:
  serviceName: web-headless
  replicas: 5
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 2  # Only update pods 2, 3, 4 (keep 0, 1 on old version)
      maxUnavailable: 1
  template:
    metadata:
      labels:
        app: web-server
    spec:
      containers:
      - name: web
        image: nginx:1.21  # Update to new version
        ports:
        - containerPort: 80
```

### Staged Updates

```yaml
# Stage 1: Update only pod 4 (canary)
kubectl patch statefulset web-server -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":4}}}}'

# Stage 2: Update pods 2, 3, 4
kubectl patch statefulset web-server -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":2}}}}'

# Stage 3: Update all pods
kubectl patch statefulset web-server -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":0}}}}'
```

### OnDelete Strategy

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: custom-update
spec:
  updateStrategy:
    type: OnDelete  # Manual control over updates
  template:
    spec:
      containers:
      - name: app
        image: myapp:v2.0  # New version
```

```bash
# Manual update process
kubectl delete pod custom-update-0  # Pod recreated with new image
kubectl delete pod custom-update-1  # Update next pod
```

## Common Use Cases

### MySQL Master-Slave Cluster

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
  labels:
    app: mysql
spec:
  serviceName: mysql-headless
  replicas: 3
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      initContainers:
      - name: init-mysql
        image: mysql:8.0
        command:
        - bash
        - "-c"
        - |
          set -ex
          # Generate mysql server-id from pod ordinal index
          [[ $(hostname) =~ -([0-9]+)$ ]] || exit 1
          ordinal=${BASH_REMATCH[1]}
          echo [mysqld] > /mnt/conf.d/server-id.cnf
          echo server-id=$((100 + $ordinal)) >> /mnt/conf.d/server-id.cnf
          # Copy appropriate conf.d files from config-map to emptyDir
          if [[ $ordinal -eq 0 ]]; then
            cp /mnt/config-map/master.cnf /mnt/conf.d/
          else
            cp /mnt/config-map/slave.cnf /mnt/conf.d/
          fi
        volumeMounts:
        - name: conf
          mountPath: /mnt/conf.d
        - name: config-map
          mountPath: /mnt/config-map
      - name: clone-mysql
        image: gcr.io/google-samples/xtrabackup:1.0
        command:
        - bash
        - "-c"
        - |
          set -ex
          # Skip the clone if data already exists
          [[ -d /var/lib/mysql/mysql ]] && exit 0
          # Skip the clone on master (ordinal index 0)
          [[ $(hostname) =~ -([0-9]+)$ ]] || exit 1
          ordinal=${BASH_REMATCH[1]}
          [[ $ordinal -eq 0 ]] && exit 0
          # Clone data from previous peer
          ncat --recv-only mysql-$(($ordinal-1)).mysql-headless 3307 | xbstream -x -C /var/lib/mysql
          xtrabackup --prepare --target-dir=/var/lib/mysql
        volumeMounts:
        - name: data
          mountPath: /var/lib/mysql
          subPath: mysql
        - name: conf
          mountPath: /etc/mysql/conf.d
      containers:
      - name: mysql
        image: mysql:8.0
        env:
        - name: MYSQL_ALLOW_EMPTY_PASSWORD
          value: "1"
        ports:
        - name: mysql
          containerPort: 3306
        volumeMounts:
        - name: data
          mountPath: /var/lib/mysql
          subPath: mysql
        - name: conf
          mountPath: /etc/mysql/conf.d
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
        livenessProbe:
          exec:
            command: ["mysqladmin", "ping"]
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
        readinessProbe:
          exec:
            command: ["mysql", "-h", "127.0.0.1", "-e", "SELECT 1"]
          initialDelaySeconds: 5
          periodSeconds: 2
          timeoutSeconds: 1
      - name: xtrabackup
        image: gcr.io/google-samples/xtrabackup:1.0
        ports:
        - name: xtrabackup
          containerPort: 3307
        command:
        - bash
        - "-c"
        - |
          set -ex
          cd /var/lib/mysql
          # Determine binlog position of cloned data, if any
          if [[ -f xtrabackup_slave_info && "x$(<xtrabackup_slave_info)" != "x" ]]; then
            # XtraBackup already generated a partial "CHANGE MASTER TO" query
            # because the --slave-info flag was set during backup
            mv xtrabackup_slave_info change_master_to.sql.in
            # Ignore xtrabackup_binlog_info in this case (it's useless)
            rm -f xtrabackup_binlog_info 2>/dev/null || true
          elif [[ -f xtrabackup_binlog_info ]]; then
            # We're cloning directly from master. Parse binlog position
            [[ $(cat xtrabackup_binlog_info) =~ ^(.*?)[[:space:]]+(.*?)$ ]] || exit 1
            rm -f xtrabackup_binlog_info 2>/dev/null
            echo "CHANGE MASTER TO MASTER_LOG_FILE='${BASH_REMATCH[1]}',\
                  MASTER_LOG_POS=${BASH_REMATCH[2]}" > change_master_to.sql.in
          fi
          # Check if we need to complete a clone by starting replication
          if [[ -f change_master_to.sql.in ]]; then
            echo "Waiting for mysqld to be ready (accepting connections)"
            until mysql -h 127.0.0.1 -e "SELECT 1"; do sleep 1; done
            echo "Initializing replication from clone position"
            mysql -h 127.0.0.1 \
                  -e "$(<change_master_to.sql.in), \
                          MASTER_HOST='mysql-0.mysql-headless', \
                          MASTER_USER='root', \
                          MASTER_PASSWORD='', \
                          MASTER_CONNECT_RETRY=10; \
                        START SLAVE;" || exit 1
            # In case of container restart, attempt this at-most-once
            mv change_master_to.sql.in change_master_to.sql.orig
          fi
          # Start a server to send backups to newly added slaves
          exec ncat --listen --keep-open --send-only --max-conns=1 3307 -c \
            "xtrabackup --backup --slave-info --stream=xbstream --host=127.0.0.1 --user=root"
        volumeMounts:
        - name: data
          mountPath: /var/lib/mysql
          subPath: mysql
        - name: conf
          mountPath: /etc/mysql/conf.d
        resources:
          requests:
            cpu: 100m
            memory: 100Mi
      volumes:
      - name: conf
        emptyDir: {}
      - name: config-map
        configMap:
          name: mysql-config
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```

### Redis Cluster

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  labels:
    app: redis
spec:
  serviceName: redis-headless
  replicas: 6
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7.0
        ports:
        - containerPort: 6379
          name: client
        - containerPort: 16379
          name: gossip
        command:
        - redis-server
        - /etc/redis/redis.conf
        - --cluster-enabled
        - --cluster-config-file
        - /data/nodes.conf
        - --cluster-node-timeout
        - "5000"
        - --appendonly
        - "yes"
        - --protected-mode
        - "no"
        volumeMounts:
        - name: data
          mountPath: /data
        - name: config
          mountPath: /etc/redis
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 250m
            memory: 256Mi
        livenessProbe:
          exec:
            command:
            - redis-cli
            - ping
          initialDelaySeconds: 30
          timeoutSeconds: 5
        readinessProbe:
          exec:
            command:
            - redis-cli
            - ping
          initialDelaySeconds: 5
          timeoutSeconds: 1
      volumes:
      - name: config
        configMap:
          name: redis-config
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi
```

### Apache Kafka

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: kafka
  labels:
    app: kafka
spec:
  serviceName: kafka-headless
  replicas: 3
  selector:
    matchLabels:
      app: kafka
  template:
    metadata:
      labels:
        app: kafka
    spec:
      containers:
      - name: kafka
        image: confluentinc/cp-kafka:7.4.0
        ports:
        - containerPort: 9092
          name: kafka
        - containerPort: 9093
          name: kafka-internal
        env:
        - name: KAFKA_BROKER_ID
          valueFrom:
            fieldRef:
              fieldPath: metadata.annotations['kafka.apache.org/broker-id']
        - name: KAFKA_ZOOKEEPER_CONNECT
          value: "zookeeper:2181"
        - name: KAFKA_ADVERTISED_LISTENERS
          value: "PLAINTEXT://$(hostname).kafka-headless:9092,PLAINTEXT_INTERNAL://$(hostname).kafka-headless:9093"
        - name: KAFKA_LISTENER_SECURITY_PROTOCOL_MAP
          value: "PLAINTEXT:PLAINTEXT,PLAINTEXT_INTERNAL:PLAINTEXT"
        - name: KAFKA_INTER_BROKER_LISTENER_NAME
          value: "PLAINTEXT_INTERNAL"
        - name: KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR
          value: "3"
        - name: KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR
          value: "3"
        - name: KAFKA_LOG_DIRS
          value: "/var/lib/kafka/data"
        volumeMounts:
        - name: data
          mountPath: /var/lib/kafka/data
        resources:
          requests:
            cpu: 250m
            memory: 512Mi
          limits:
            cpu: 500m
            memory: 1Gi
        readinessProbe:
          tcpSocket:
            port: 9092
          initialDelaySeconds: 30
          periodSeconds: 10
      initContainers:
      - name: init-broker-id
        image: busybox
        command:
        - sh
        - -c
        - |
          # Extract broker ID from hostname (kafka-0 -> 0, kafka-1 -> 1, etc.)
          BROKER_ID=$(echo $HOSTNAME | grep -o '[0-9]*$')
          echo "kafka.apache.org/broker-id: \"$BROKER_ID\"" > /tmp/annotations
        env:
        - name: HOSTNAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```

### PostgreSQL Primary-Replica

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgresql
  labels:
    app: postgresql
spec:
  serviceName: postgresql-headless
  replicas: 3
  selector:
    matchLabels:
      app: postgresql
  template:
    metadata:
      labels:
        app: postgresql
    spec:
      initContainers:
      - name: init-postgresql
        image: postgres:15
        command:
        - bash
        - -c
        - |
          set -e
          [[ $(hostname) =~ -([0-9]+)$ ]] || exit 1
          ordinal=${BASH_REMATCH[1]}
          
          if [[ $ordinal -eq 0 ]]; then
            echo "Initializing primary database"
            export PGDATA=/var/lib/postgresql/data/pgdata
            if [[ ! -d $PGDATA ]]; then
              initdb --auth-host=scram-sha-256 --auth-local=peer --username=postgres
              echo "host replication replicator 0.0.0.0/0 scram-sha-256" >> $PGDATA/pg_hba.conf
              echo "wal_level = replica" >> $PGDATA/postgresql.conf
              echo "max_wal_senders = 3" >> $PGDATA/postgresql.conf
              echo "max_replication_slots = 3" >> $PGDATA/postgresql.conf
            fi
          else
            echo "Initializing replica database from primary"
            export PGDATA=/var/lib/postgresql/data/pgdata
            if [[ ! -d $PGDATA ]]; then
              pg_basebackup -h postgresql-0.postgresql-headless -D $PGDATA -U replicator -W -v -P
              echo "standby_mode = 'on'" >> $PGDATA/recovery.conf
              echo "primary_conninfo = 'host=postgresql-0.postgresql-headless port=5432 user=replicator'" >> $PGDATA/recovery.conf
            fi
          fi
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgresql-secret
              key: password
        - name: PGPASSWORD
          valueFrom:
            secretKeyRef:
              name: postgresql-secret
              key: replication-password
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
      containers:
      - name: postgresql
        image: postgres:15
        ports:
        - name: postgresql
          containerPort: 5432
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgresql-secret
              key: password
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
        resources:
          requests:
            cpu: 250m
            memory: 256Mi
          limits:
            cpu: 500m
            memory: 512Mi
        livenessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - postgres
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - postgres
          initialDelaySeconds: 5
          periodSeconds: 5
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 20Gi
```

## Best Practices

### Resource Management

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: optimized-statefulset
spec:
  serviceName: optimized-headless
  replicas: 3
  template:
    spec:
      containers:
      - name: app
        image: myapp:latest
        resources:
          requests:
            cpu: 500m
            memory: 1Gi
          limits:
            cpu: 1000m
            memory: 2Gi
        # Resource-aware configuration
        env:
        - name: MEMORY_LIMIT
          valueFrom:
            resourceFieldRef:
              resource: limits.memory
        - name: CPU_LIMIT
          valueFrom:
            resourceFieldRef:
              resource: limits.cpu
      # Anti-affinity to spread pods across nodes
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values: ["myapp"]
              topologyKey: kubernetes.io/hostname
```

### Security Configuration

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: secure-statefulset
spec:
  serviceName: secure-headless
  template:
    spec:
      serviceAccountName: statefulset-service-account
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 2000
      containers:
      - name: app
        image: secure-app:latest
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          capabilities:
            drop: ["ALL"]
        volumeMounts:
        - name: data
          mountPath: /data
        - name: tmp
          mountPath: /tmp
      volumes:
      - name: tmp
        emptyDir: {}
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```

### Monitoring and Health Checks

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: monitored-statefulset
  labels:
    app: monitored-app
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
spec:
  serviceName: monitored-headless
  template:
    spec:
      containers:
      - name: app
        image: monitored-app:latest
        ports:
        - containerPort: 8080
          name: http
        - containerPort: 9090
          name: metrics
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 3
        startupProbe:
          httpGet:
            path: /startup
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 30
```

## Troubleshooting

### Common Issues

#### 1. StatefulSet Not Scaling

```bash
# Check StatefulSet status
kubectl get statefulset myapp -o wide

# Check Pod status
kubectl get pods -l app=myapp

# Check events
kubectl describe statefulset myapp

# Check PVC status
kubectl get pvc -l app=myapp

# Check storage class
kubectl get storageclass
```

#### 2. Pods Stuck in Pending

```bash
# Check Pod events
kubectl describe pod myapp-0

# Check node resources
kubectl describe nodes

# Check PVC binding
kubectl get pvc
kubectl describe pvc data-myapp-0

# Check storage provisioner
kubectl get events --field-selector reason=ProvisioningFailed
```

#### 3. Pods Not Starting in Order

```bash
# Check pod management policy
kubectl get statefulset myapp -o jsonpath='{.spec.podManagementPolicy}'

# Check readiness probes
kubectl describe pod myapp-0 | grep -A 10 Readiness

# Check dependencies
kubectl get pod myapp-0 -o yaml | grep -A 5 readinessProbe
```

### Debugging Commands

```bash
# List all StatefulSets
kubectl get statefulsets
kubectl get sts  # Short form

# Get StatefulSet details
kubectl describe statefulset myapp

# Check StatefulSet status
kubectl get statefulset myapp -o yaml

# View StatefulSet Pods
kubectl get pods -l app=myapp
kubectl get pods -l statefulset.kubernetes.io/pod-name=myapp-0

# Check PVCs
kubectl get pvc -l app=myapp
kubectl describe pvc data-myapp-0

# Scale StatefulSet
kubectl scale statefulset myapp --replicas=5

# Update StatefulSet image
kubectl patch statefulset myapp -p '{"spec":{"template":{"spec":{"containers":[{"name":"myapp","image":"myapp:v2.0"}]}}}}'

# Rolling restart
kubectl rollout restart statefulset myapp

# Check rollout status
kubectl rollout status statefulset myapp

# View rollout history
kubectl rollout history statefulset myapp

# Rollback
kubectl rollout undo statefulset myapp

# Delete StatefulSet (keep PVCs)
kubectl delete statefulset myapp --cascade=orphan

# Force delete stuck Pod
kubectl delete pod myapp-0 --grace-period=0 --force
```

### Performance Monitoring

```bash
# Check resource usage
kubectl top pods -l app=myapp

# Monitor StatefulSet metrics
kubectl get statefulset myapp -w

# Check Pod startup times
kubectl get pods -l app=myapp -o custom-columns=NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status,START_TIME:.status.startTime

# Monitor PVC usage
kubectl get pvc -l app=myapp -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,CAPACITY:.status.capacity.storage
```

---

## References

- [Kubernetes Official Documentation: StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [Kubernetes API Reference: StatefulSet](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.28/#statefulset-v1-apps)
- [StatefulSet Basics Tutorial](https://kubernetes.io/docs/tutorials/stateful-application/basic-stateful-set/)
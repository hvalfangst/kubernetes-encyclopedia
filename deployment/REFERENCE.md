# Kubernetes Deployment Resource Documentation

## Table of Contents
- [Overview](#overview)
- [API Specification](#api-specification)
- [Field Reference](#field-reference)
- [Deployment Strategies](#deployment-strategies)
- [Scaling and Autoscaling](#scaling-and-autoscaling)
- [Rollouts and Rollbacks](#rollouts-and-rollbacks)
- [Common Use Cases](#common-use-cases)
- [Best Practices](#best-practices)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

## Overview

A **Deployment** manages a set of Pods for stateless application workloads, providing declarative updates for Pods and ReplicaSets. It allows defining a "desired state" that the Deployment Controller gradually implements.

### Key Features
- Declarative Pod and ReplicaSet management
- Rolling updates with zero downtime
- Rollback capabilities to previous versions
- Horizontal scaling and autoscaling support
- Built-in health checks and readiness probes
- Progressive deployment strategies

### When to Use Deployments
- **Web applications**: Frontend and backend services
- **API services**: RESTful APIs and microservices
- **Stateless workloads**: Applications without persistent state
- **Batch processing**: Parallel processing applications
- **Background services**: Queue workers and processors
- **Development environments**: Testing and staging deployments

## API Specification

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: string
  namespace: string
  labels: {}
  annotations: {}
spec:
  replicas: integer                    # Number of desired Pod replicas (default: 1)
  selector:                           # Required: Label selector to identify managed Pods
    matchLabels: {}
    matchExpressions: []
  template:                           # Required: Pod template specification
    metadata:
      labels: {}
      annotations: {}
    spec: {}
  strategy:                           # Update strategy
    type: string                      # RollingUpdate or Recreate
    rollingUpdate:
      maxUnavailable: string/integer  # Max pods unavailable during update
      maxSurge: string/integer        # Max pods above desired replica count
  revisionHistoryLimit: integer       # Number of old ReplicaSets to retain
  progressDeadlineSeconds: integer    # Max time for deployment to make progress
  paused: boolean                     # Pause/resume deployment
status:
  observedGeneration: integer         # Generation observed by controller
  replicas: integer                   # Total number of replicas
  updatedReplicas: integer           # Number of updated replicas
  readyReplicas: integer             # Number of ready replicas
  availableReplicas: integer         # Number of available replicas
  conditions: []                     # Deployment conditions
```

## Field Reference

### Metadata Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Name of the Deployment resource |
| `namespace` | string | Namespace where the Deployment resides |
| `labels` | map[string]string | Key-value pairs for organizing resources |
| `annotations` | map[string]string | Additional metadata for the resource |

### Spec Fields

#### replicas
**Type**: `integer`  
**Default**: `1`  
**Description**: Number of desired Pod replicas

```yaml
spec:
  replicas: 3  # Run 3 instances of the application
```

**Use Cases**:
- **High Availability**: Multiple replicas for redundancy
- **Load Distribution**: Spread load across multiple instances
- **Performance**: Handle increased traffic with more replicas

#### selector (Required)
**Type**: `LabelSelector`  
**Description**: Label selector to identify which Pods belong to this Deployment

```yaml
spec:
  selector:
    matchLabels:
      app: nginx
      version: v1
    matchExpressions:
    - key: environment
      operator: In
      values: ["production", "staging"]
```

**Best Practices**:
- Use consistent, descriptive labels
- Ensure selector matches Pod template labels
- Avoid overlapping selectors between Deployments

#### template (Required)
**Type**: `PodTemplateSpec`  
**Description**: Template for the Pods that will be created

```yaml
spec:
  template:
    metadata:
      labels:
        app: nginx
        version: v1.0
    spec:
      containers:
      - name: nginx
        image: nginx:1.21
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "250m"
          limits:
            memory: "128Mi"
            cpu: "500m"
```

### strategy
**Type**: `DeploymentStrategy`  
**Description**: Strategy for replacing old Pods with new ones

#### RollingUpdate (Default)
Updates Pods gradually to maintain availability:

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 25%  # Can be percentage or absolute number
      maxSurge: 25%        # Can be percentage or absolute number
```

**Use Cases**:
- **Zero-downtime deployments**: Maintain service availability
- **Gradual rollouts**: Test new versions progressively
- **Resource-constrained environments**: Control resource usage during updates

**Configuration Examples**:

```yaml
# Conservative rolling update
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 1
    maxSurge: 1

# Aggressive rolling update
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 50%
    maxSurge: 50%
```

#### Recreate
Terminates all existing Pods before creating new ones:

```yaml
spec:
  strategy:
    type: Recreate
```

**Use Cases**:
- **Resource constraints**: When cluster can't run old and new Pods simultaneously
- **Exclusive access requirements**: Applications that can't run multiple versions
- **Development environments**: Simple deployment strategy

### revisionHistoryLimit
**Type**: `integer`  
**Default**: `10`  
**Description**: Number of old ReplicaSets to retain for rollback

```yaml
spec:
  revisionHistoryLimit: 5  # Keep last 5 deployment revisions
```

**Use Cases**:
- **Storage optimization**: Reduce etcd usage in large clusters
- **Audit requirements**: Maintain deployment history
- **Rollback capabilities**: Enable quick recovery from issues

### progressDeadlineSeconds
**Type**: `integer`  
**Default**: `600` (10 minutes)  
**Description**: Maximum time for deployment to make progress

```yaml
spec:
  progressDeadlineSeconds: 300  # 5 minutes timeout
```

**Use Cases**:
- **Fast failure detection**: Quickly identify stuck deployments
- **CI/CD integration**: Set appropriate timeouts for automation
- **Resource management**: Prevent indefinitely running deployments

### paused
**Type**: `boolean`  
**Default**: `false`  
**Description**: Pause/resume deployment updates

```yaml
spec:
  paused: true  # Pause deployment updates
```

**Use Cases**:
- **Debugging**: Stop updates while investigating issues
- **Maintenance windows**: Pause during system maintenance
- **Manual verification**: Pause between deployment stages

## Deployment Strategies

### Rolling Update Strategy

The default strategy that gradually replaces old Pods with new ones:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rolling-update-example
spec:
  replicas: 6
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 2  # At most 2 pods unavailable
      maxSurge: 2        # At most 2 extra pods during update
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
      - name: web
        image: nginx:1.21
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
```

### Blue-Green Deployment Pattern

While not natively supported, can be implemented using multiple Deployments:

```yaml
# Blue (current) deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-blue
  labels:
    version: blue
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
      version: blue
  template:
    metadata:
      labels:
        app: myapp
        version: blue
    spec:
      containers:
      - name: app
        image: myapp:v1.0
---
# Green (new) deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-green
  labels:
    version: green
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
      version: green
  template:
    metadata:
      labels:
        app: myapp
        version: green
    spec:
      containers:
      - name: app
        image: myapp:v2.0
```

### Canary Deployment Pattern

Deploy new version to a subset of users:

```yaml
# Main deployment (90% traffic)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-main
spec:
  replicas: 9
  selector:
    matchLabels:
      app: myapp
      track: stable
  template:
    metadata:
      labels:
        app: myapp
        track: stable
    spec:
      containers:
      - name: app
        image: myapp:v1.0
---
# Canary deployment (10% traffic)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-canary
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
      track: canary
  template:
    metadata:
      labels:
        app: myapp
        track: canary
    spec:
      containers:
      - name: app
        image: myapp:v2.0
```

## Scaling and Autoscaling

### Manual Scaling

```bash
# Scale deployment to 5 replicas
kubectl scale deployment myapp --replicas=5

# Scale using YAML
kubectl patch deployment myapp -p '{"spec":{"replicas":5}}'
```

### Horizontal Pod Autoscaler (HPA)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: myapp-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

### Vertical Pod Autoscaler (VPA)

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: myapp-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp
  updatePolicy:
    updateMode: "Auto"
  resourcePolicy:
    containerPolicies:
    - containerName: app
      maxAllowed:
        cpu: 1
        memory: 2Gi
      minAllowed:
        cpu: 100m
        memory: 50Mi
```

## Rollouts and Rollbacks

### Viewing Rollout Status

```bash
# Check rollout status
kubectl rollout status deployment/myapp

# View rollout history
kubectl rollout history deployment/myapp

# View specific revision
kubectl rollout history deployment/myapp --revision=2
```

### Rolling Back Deployments

```bash
# Rollback to previous revision
kubectl rollout undo deployment/myapp

# Rollback to specific revision
kubectl rollout undo deployment/myapp --to-revision=2

# Pause rollout
kubectl rollout pause deployment/myapp

# Resume rollout
kubectl rollout resume deployment/myapp
```

### Deployment with Rollback Configuration

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rollback-example
  annotations:
    deployment.kubernetes.io/revision: "1"
spec:
  replicas: 3
  revisionHistoryLimit: 10  # Keep 10 revisions for rollback
  progressDeadlineSeconds: 300
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: app
        image: myapp:v1.0
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

## Common Use Cases

### Web Application Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  labels:
    app: web-app
    tier: frontend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
        tier: frontend
    spec:
      containers:
      - name: web
        image: nginx:1.21
        ports:
        - containerPort: 80
        env:
        - name: ENVIRONMENT
          value: "production"
        resources:
          requests:
            memory: "128Mi"
            cpu: "250m"
          limits:
            memory: "256Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
```

### API Service Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-service
  labels:
    app: api-service
    tier: backend
spec:
  replicas: 5
  selector:
    matchLabels:
      app: api-service
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 2
  template:
    metadata:
      labels:
        app: api-service
        tier: backend
    spec:
      containers:
      - name: api
        image: myapi:v2.1
        ports:
        - containerPort: 8080
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: url
        - name: API_KEY
          valueFrom:
            secretKeyRef:
              name: api-secret
              key: key
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
```

### Multi-Container Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: multi-container-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: multi-container-app
  template:
    metadata:
      labels:
        app: multi-container-app
    spec:
      containers:
      - name: web-server
        image: nginx:1.21
        ports:
        - containerPort: 80
        volumeMounts:
        - name: shared-data
          mountPath: /usr/share/nginx/html
      - name: content-puller
        image: busybox
        command: ['sh', '-c', 'while true; do wget -O /shared/index.html http://example.com; sleep 300; done']
        volumeMounts:
        - name: shared-data
          mountPath: /shared
      volumes:
      - name: shared-data
        emptyDir: {}
```

## Best Practices

### Resource Management

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: resource-managed-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: resource-managed-app
  template:
    metadata:
      labels:
        app: resource-managed-app
    spec:
      containers:
      - name: app
        image: myapp:latest
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        # Always define health checks
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          successThreshold: 1
          failureThreshold: 3
```

### Security Best Practices

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: secure-app
  template:
    metadata:
      labels:
        app: secure-app
    spec:
      serviceAccountName: secure-service-account
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 2000
      containers:
      - name: app
        image: myapp:v1.0
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          capabilities:
            drop:
            - ALL
        volumeMounts:
        - name: tmp-volume
          mountPath: /tmp
        - name: cache-volume
          mountPath: /var/cache/app
      volumes:
      - name: tmp-volume
        emptyDir: {}
      - name: cache-volume
        emptyDir: {}
```

### Configuration Management

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: config-managed-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: config-managed-app
  template:
    metadata:
      labels:
        app: config-managed-app
    spec:
      containers:
      - name: app
        image: myapp:v1.0
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: database-url
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: log-level
        volumeMounts:
        - name: config-volume
          mountPath: /etc/config
          readOnly: true
        - name: secrets-volume
          mountPath: /etc/secrets
          readOnly: true
      volumes:
      - name: config-volume
        configMap:
          name: app-config
      - name: secrets-volume
        secret:
          secretName: app-secrets
```

## Troubleshooting

### Common Issues

#### 1. Deployment Not Rolling Out

```bash
# Check deployment status
kubectl get deployment myapp -o wide

# Check rollout status
kubectl rollout status deployment/myapp

# Check events
kubectl get events --field-selector involvedObject.name=myapp

# Describe deployment
kubectl describe deployment myapp

# Check ReplicaSet status
kubectl get rs -l app=myapp

# Check Pod status
kubectl get pods -l app=myapp
```

#### 2. Pods Not Starting

```bash
# Check Pod status
kubectl get pods -l app=myapp -o wide

# Describe problematic Pod
kubectl describe pod <pod-name>

# Check Pod logs
kubectl logs <pod-name> --previous

# Check resource quotas
kubectl describe quota

# Check node capacity
kubectl describe nodes
```

#### 3. Image Pull Issues

```bash
# Check if image exists and is accessible
kubectl describe pod <pod-name> | grep -A 10 Events

# Verify image pull secrets
kubectl get secrets

# Check service account
kubectl describe serviceaccount default
```

### Debugging Commands

```bash
# List all deployments
kubectl get deployments

# Get deployment details
kubectl describe deployment myapp

# Check deployment history
kubectl rollout history deployment/myapp

# View current ReplicaSets
kubectl get rs -l app=myapp

# Scale deployment manually
kubectl scale deployment myapp --replicas=5

# Update deployment image
kubectl set image deployment/myapp container=myapp:v2.0

# Rollback deployment
kubectl rollout undo deployment/myapp

# Pause/resume deployment
kubectl rollout pause deployment/myapp
kubectl rollout resume deployment/myapp

# Edit deployment live
kubectl edit deployment myapp

# Export deployment YAML
kubectl get deployment myapp -o yaml > myapp-deployment.yaml
```

### Performance Monitoring

```bash
# Check resource usage
kubectl top pods -l app=myapp

# Monitor deployment metrics
kubectl get deployment myapp -w

# Check HPA status (if configured)
kubectl get hpa myapp

# View Pod resource utilization
kubectl describe pod <pod-name> | grep -A 10 Containers
```

---

## References

- [Kubernetes Official Documentation: Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Kubernetes API Reference: Deployment](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.28/#deployment-v1-apps)
- [Deployment Strategies Guide](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#strategy)
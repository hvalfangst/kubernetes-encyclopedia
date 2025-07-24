# Kubernetes Service Resource Documentation

## Table of Contents
- [Overview](#overview)
- [API Specification](#api-specification)
- [Field Reference](#field-reference)
- [Service Types](#service-types)
- [Service Discovery](#service-discovery)
- [Load Balancing](#load-balancing)
- [Common Use Cases](#common-use-cases)
- [Best Practices](#best-practices)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

## Overview

A **Service** is a method for exposing network applications running in Pods, providing stable network access to a dynamic set of Pods and solving the problem of Pod IP address volatility.

### Key Features
- Stable network endpoint for dynamic Pod sets
- Load balancing across multiple Pod replicas
- Service discovery through DNS and environment variables
- Multiple exposure types (internal and external)
- Integration with cloud provider load balancers
- Session affinity and connection routing

### When to Use Services
- **Frontend applications**: Expose web applications to users
- **API services**: Provide stable endpoints for microservices
- **Database access**: Connect applications to database pods
- **Inter-service communication**: Enable microservice communication
- **Load balancing**: Distribute traffic across multiple replicas
- **Service discovery**: Enable dynamic service location

## API Specification

```yaml
apiVersion: v1
kind: Service
metadata:
  name: string
  namespace: string
  labels: {}
  annotations: {}
spec:
  selector: {}                        # Label selector to target Pods
  ports:                             # Required: Port configuration
  - name: string                     # Port name (optional)
    protocol: string                 # TCP, UDP, or SCTP (default: TCP)
    port: integer                    # Service port (required)
    targetPort: string/integer       # Pod port (default: same as port)
    nodePort: integer               # Node port (NodePort/LoadBalancer only)
  type: string                       # ClusterIP, NodePort, LoadBalancer, ExternalName
  clusterIP: string                  # Cluster-internal IP address
  clusterIPs: []                     # For dual-stack configurations
  externalIPs: []                    # External IP addresses
  sessionAffinity: string            # None or ClientIP
  sessionAffinityConfig: {}          # Session affinity configuration
  externalName: string               # External DNS name (ExternalName only)
  externalTrafficPolicy: string      # Cluster or Local
  internalTrafficPolicy: string      # Cluster or Local
  ipFamilies: []                     # IPv4, IPv6 (dual-stack)
  ipFamilyPolicy: string             # SingleStack, PreferDualStack, RequireDualStack
status:
  loadBalancer:                      # LoadBalancer status
    ingress: []                      # External load balancer ingress points
```

## Field Reference

### Metadata Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Name of the Service resource |
| `namespace` | string | Namespace where the Service resides |
| `labels` | map[string]string | Key-value pairs for organizing resources |
| `annotations` | map[string]string | Additional metadata for the resource |

### Spec Fields

#### selector
**Type**: `map[string]string`  
**Description**: Label selector to identify target Pods

```yaml
spec:
  selector:
    app: nginx
    version: v1
```

**Use Cases**:
- **Pod targeting**: Select specific Pods to receive traffic
- **Version control**: Route traffic to specific application versions
- **Environment separation**: Target development vs production Pods

#### ports (Required)
**Type**: `[]ServicePort`  
**Description**: List of ports that the Service exposes

```yaml
spec:
  ports:
  - name: http
    protocol: TCP
    port: 80
    targetPort: 8080
  - name: https
    protocol: TCP
    port: 443
    targetPort: 8443
```

**Port Fields**:
- `name`: Port name for reference (optional but recommended)
- `protocol`: TCP, UDP, or SCTP (default: TCP)
- `port`: Port that the Service exposes
- `targetPort`: Port on the Pod (default: same as `port`)
- `nodePort`: Node port for NodePort/LoadBalancer services

#### type
**Type**: `string`  
**Default**: `ClusterIP`  
**Options**: `ClusterIP`, `NodePort`, `LoadBalancer`, `ExternalName`

**ClusterIP (Default)**:
- Exposes Service on a cluster-internal IP
- Only reachable from within the cluster

```yaml
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 8080
```

**NodePort**:
- Exposes Service on each Node's IP at a static port
- Accessible from outside the cluster via `<NodeIP>:<NodePort>`

```yaml
spec:
  type: NodePort
  ports:
  - port: 80
    targetPort: 8080
    nodePort: 30080  # Optional: auto-assigned if not specified
```

**LoadBalancer**:
- Exposes Service externally using cloud provider's load balancer
- Creates NodePort and ClusterIP services automatically

```yaml
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 8080
```

**ExternalName**:
- Maps Service to DNS name, returns CNAME record
- No proxying or load balancing

```yaml
spec:
  type: ExternalName
  externalName: api.example.com
```

#### sessionAffinity
**Type**: `string`  
**Default**: `None`  
**Options**: `None`, `ClientIP`

**None**: Distribute requests randomly across Pods
**ClientIP**: Route requests from same client IP to same Pod

```yaml
spec:
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 3600  # Session timeout
```

#### externalTrafficPolicy
**Type**: `string`  
**Default**: `Cluster`  
**Options**: `Cluster`, `Local`  
**Applies to**: NodePort and LoadBalancer services

**Cluster**: Traffic can be routed to any node
**Local**: Traffic only goes to Pods on the same node

```yaml
spec:
  type: LoadBalancer
  externalTrafficPolicy: Local  # Preserve source IP
```

## Service Types

### ClusterIP Service

Default service type for internal cluster communication:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-service
spec:
  type: ClusterIP
  selector:
    app: backend
    tier: api
  ports:
  - name: http
    protocol: TCP
    port: 80
    targetPort: 8080
  - name: metrics
    protocol: TCP
    port: 9090
    targetPort: 9090
```

**Use Cases**:
- Internal microservice communication
- Database connections
- Cache services
- Internal APIs

### NodePort Service

Exposes service on all nodes at a specific port:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-nodeport
spec:
  type: NodePort
  selector:
    app: web
  ports:
  - name: http
    protocol: TCP
    port: 80
    targetPort: 8080
    nodePort: 30080  # Accessible via <NodeIP>:30080
```

**Use Cases**:
- Development and testing environments
- Direct external access without load balancer
- Legacy applications requiring specific ports
- Cost-effective external exposure

### LoadBalancer Service

Integrates with cloud provider load balancers:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-loadbalancer
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
spec:
  type: LoadBalancer
  selector:
    app: web
  ports:
  - name: http
    protocol: TCP
    port: 80
    targetPort: 8080
  - name: https
    protocol: TCP
    port: 443
    targetPort: 8443
  externalTrafficPolicy: Local  # Preserve source IP
```

**Use Cases**:
- Production applications requiring external access
- Applications needing cloud provider load balancer features
- High-availability web applications
- Services requiring SSL termination at load balancer

### ExternalName Service

Maps service to external DNS name:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: external-api
spec:
  type: ExternalName
  externalName: api.external-service.com
  ports:
  - port: 80
```

**Use Cases**:
- Integration with external services
- Database services outside the cluster
- Third-party APIs
- Migration scenarios

### Headless Service

Service without a cluster IP, returns Pod IPs directly:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: database-headless
spec:
  clusterIP: None  # Makes it headless
  selector:
    app: database
  ports:
  - name: mysql
    protocol: TCP
    port: 3306
    targetPort: 3306
```

**Use Cases**:
- StatefulSet services
- Database clustering
- Direct Pod communication
- Service discovery for stateful applications

## Service Discovery

### DNS-Based Discovery

Kubernetes automatically creates DNS records for services:

```yaml
# Service creates DNS record: <service-name>.<namespace>.svc.cluster.local
# Example: web-service.default.svc.cluster.local

# Within same namespace: just use service name
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: client
    image: busybox
    command: ['sh', '-c', 'wget -q -O- http://web-service/']

# Cross-namespace: use full service name
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: client
    image: busybox
    command: ['sh', '-c', 'wget -q -O- http://api-service.production.svc.cluster.local/']
```

### Environment Variables

Kubernetes injects service information as environment variables:

```yaml
# For service named 'web-service' on port 80:
# WEB_SERVICE_SERVICE_HOST=10.96.1.100
# WEB_SERVICE_SERVICE_PORT=80
# WEB_SERVICE_PORT_80_TCP=tcp://10.96.1.100:80
# WEB_SERVICE_PORT_80_TCP_PROTO=tcp
# WEB_SERVICE_PORT_80_TCP_PORT=80
# WEB_SERVICE_PORT_80_TCP_ADDR=10.96.1.100

apiVersion: v1
kind: Pod
spec:
  containers:
  - name: client
    image: busybox
    command: ['sh', '-c', 'echo $WEB_SERVICE_SERVICE_HOST']
```

## Load Balancing

### Round-Robin Load Balancing (Default)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: load-balanced-service
spec:
  selector:
    app: web-app
  ports:
  - port: 80
    targetPort: 8080
  # No sessionAffinity = round-robin distribution
```

### Session Affinity

```yaml
apiVersion: v1
kind: Service
metadata:
  name: sticky-session-service
spec:
  selector:
    app: web-app
  ports:
  - port: 80
    targetPort: 8080
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 3600  # 1 hour session timeout
```

### External Traffic Policy

```yaml
apiVersion: v1
kind: Service
metadata:
  name: local-traffic-service
spec:
  type: LoadBalancer
  externalTrafficPolicy: Local  # Only route to local node Pods
  selector:
    app: web-app
  ports:
  - port: 80
    targetPort: 8080
```

## Common Use Cases

### Frontend Web Application

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
  labels:
    app: frontend
    tier: web
spec:
  type: LoadBalancer
  selector:
    app: frontend
  ports:
  - name: http
    protocol: TCP
    port: 80
    targetPort: 3000
  - name: https
    protocol: TCP
    port: 443
    targetPort: 3000
  externalTrafficPolicy: Local
```

### Backend API Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: api-service
  labels:
    app: api
    tier: backend
spec:
  type: ClusterIP
  selector:
    app: api
    version: v1
  ports:
  - name: http
    protocol: TCP
    port: 80
    targetPort: 8080
  - name: grpc
    protocol: TCP
    port: 9090
    targetPort: 9090
```

### Database Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: database-service
  labels:
    app: database
    tier: data
spec:
  type: ClusterIP
  selector:
    app: mysql
    role: master
  ports:
  - name: mysql
    protocol: TCP
    port: 3306
    targetPort: 3306
  sessionAffinity: ClientIP  # Maintain connection to same DB instance
```

### Multi-Port Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: multi-port-service
spec:
  selector:
    app: multi-service
  ports:
  - name: web
    protocol: TCP
    port: 80
    targetPort: 8080
  - name: admin
    protocol: TCP
    port: 8443
    targetPort: 8443
  - name: metrics
    protocol: TCP
    port: 9090
    targetPort: 9090
  - name: grpc
    protocol: TCP
    port: 50051
    targetPort: 50051
```

### Service with Health Checks

```yaml
apiVersion: v1
kind: Service
metadata:
  name: health-checked-service
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-path: "/health"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-port: "8080"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol: "HTTP"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-interval: "30"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-timeout: "5"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-healthy-threshold: "2"
    service.beta.kubernetes.io/aws-load-balancer-healthcheck-unhealthy-threshold: "3"
spec:
  type: LoadBalancer
  selector:
    app: web-app
  ports:
  - port: 80
    targetPort: 8080
```

## Best Practices

### Service Naming and Labels

```yaml
apiVersion: v1
kind: Service
metadata:
  name: user-api-service  # Descriptive, kebab-case naming
  labels:
    app.kubernetes.io/name: user-api
    app.kubernetes.io/instance: production
    app.kubernetes.io/version: "v1.2.3"
    app.kubernetes.io/component: api
    app.kubernetes.io/part-of: user-management
    app.kubernetes.io/managed-by: helm
  annotations:
    service.beta.kubernetes.io/external-traffic: "OnlyLocal"
spec:
  selector:
    app.kubernetes.io/name: user-api
    app.kubernetes.io/instance: production
  ports:
  - name: http-api
    protocol: TCP
    port: 80
    targetPort: http
```

### Resource Management

```yaml
apiVersion: v1
kind: Service
metadata:
  name: resource-managed-service
  annotations:
    # Cloud provider specific annotations
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "tcp"
    service.beta.kubernetes.io/aws-load-balancer-connection-idle-timeout: "60"
spec:
  type: LoadBalancer
  selector:
    app: web-app
  ports:
  - name: http
    protocol: TCP
    port: 80
    targetPort: 8080
  externalTrafficPolicy: Local
  sessionAffinity: ClientIP
  sessionAffinityConfig:
    clientIP:
      timeoutSeconds: 1800
```

### Security Configuration

```yaml
apiVersion: v1
kind: Service
metadata:
  name: secure-service
  annotations:
    # SSL/TLS annotations
    service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "arn:aws:acm:region:account:certificate/cert-id"
    service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "https"
    service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "http"
spec:
  type: LoadBalancer
  selector:
    app: secure-app
  ports:
  - name: https
    protocol: TCP
    port: 443
    targetPort: 8080
  - name: http
    protocol: TCP
    port: 80
    targetPort: 8080
```

### Internal Service Communication

```yaml
apiVersion: v1
kind: Service
metadata:
  name: internal-api
  annotations:
    service.beta.kubernetes.io/topology-aware-hints: auto
spec:
  type: ClusterIP
  selector:
    app: internal-api
  internalTrafficPolicy: Local  # Keep traffic within node when possible
  ports:
  - name: api
    protocol: TCP
    port: 8080
    targetPort: api
```

## Troubleshooting

### Common Issues

#### 1. Service Not Accessible

```bash
# Check if Service exists
kubectl get service myservice -o wide

# Verify Service endpoints
kubectl get endpoints myservice

# Check if Pods are selected by Service
kubectl get pods -l app=myapp

# Verify Pod labels match Service selector
kubectl describe service myservice
kubectl get pods -l app=myapp --show-labels

# Test Service connectivity from within cluster
kubectl run test-pod --image=busybox --rm -it -- wget -q -O- http://myservice/
```

#### 2. External Service Not Reachable

```bash
# Check LoadBalancer status
kubectl get service myservice -o wide

# Verify external IP assignment
kubectl describe service myservice

# Check cloud provider load balancer
# (AWS/GCP/Azure specific commands)

# Verify security groups/firewall rules
# Check that NodePort range is accessible (30000-32767)
```

#### 3. No Endpoints Available

```bash
# Check if Pods are running and ready
kubectl get pods -l app=myapp

# Verify Pod readiness probes
kubectl describe pod <pod-name>

# Check Service selector
kubectl get service myservice -o yaml | grep -A 5 selector

# Verify Pod labels
kubectl get pods -l app=myapp --show-labels
```

### Debugging Commands

```bash
# List all services
kubectl get services
kubectl get svc  # Short form

# Get service details
kubectl describe service myservice

# Check service endpoints
kubectl get endpoints
kubectl describe endpoints myservice

# Test DNS resolution
kubectl run dns-test --image=busybox --rm -it -- nslookup myservice

# Test service connectivity
kubectl run curl-test --image=curlimages/curl --rm -it -- curl http://myservice/

# Check service logs (for LoadBalancer type)
kubectl describe service myservice | grep Events

# Port forward for local testing
kubectl port-forward service/myservice 8080:80

# View service in different output formats
kubectl get service myservice -o yaml
kubectl get service myservice -o json
kubectl get service myservice -o wide

# Check service across all namespaces
kubectl get services --all-namespaces

# Monitor service endpoints
kubectl get endpoints myservice -w
```

### Performance Testing

```bash
# Load test from within cluster
kubectl run load-test --image=busybox --rm -it -- \
  sh -c 'for i in $(seq 1 100); do wget -q -O- http://myservice/ && echo "Request $i completed"; done'

# Check service resource usage
kubectl top pods -l app=myapp

# Monitor service metrics (if metrics-server available)
kubectl get --raw /apis/metrics.k8s.io/v1beta1/namespaces/default/pods | jq '.items[] | select(.metadata.labels.app=="myapp")'
```

### Network Troubleshooting

```bash
# Check kube-proxy configuration
kubectl get configmap kube-proxy-config -n kube-system -o yaml

# Verify iptables rules (on nodes)
sudo iptables -t nat -L | grep myservice

# Check if kube-dns/CoreDNS is working
kubectl get pods -n kube-system | grep dns

# Test cross-namespace service access
kubectl run test --image=busybox --rm -it -- \
  wget -q -O- http://myservice.other-namespace.svc.cluster.local/
```

---

## References

- [Kubernetes Official Documentation: Services](https://kubernetes.io/docs/concepts/services-networking/service/)
- [Kubernetes API Reference: Service](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.28/#service-v1-core)
- [Service Types Guide](https://kubernetes.io/docs/concepts/services-networking/service/#publishing-services-service-types)
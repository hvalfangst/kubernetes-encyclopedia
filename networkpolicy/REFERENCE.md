# Kubernetes NetworkPolicy Resource Documentation

## Table of Contents
- [Overview](#overview)
- [API Specification](#api-specification)
- [Field Reference](#field-reference)
- [Traffic Rules](#traffic-rules)
- [Common Use Cases](#common-use-cases)
- [Best Practices](#best-practices)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

## Overview

A **NetworkPolicy** is a specification of how groups of pods are allowed to communicate with each other and other network endpoints. NetworkPolicies use labels to select pods and define rules which specify what traffic is allowed to the selected pods.

### Key Features
- Pod-to-pod traffic control using labels
- Ingress and egress traffic rules
- Protocol and port-based filtering
- Namespace and external endpoint isolation
- Default deny/allow behaviors
- CNI plugin implementation dependent

### When to Use NetworkPolicies
- **Micro-segmentation**: Isolate application tiers (frontend, backend, database)
- **Security compliance**: Implement zero-trust networking
- **Multi-tenancy**: Isolate tenant workloads
- **Development environments**: Prevent cross-environment communication
- **Regulatory requirements**: Meet security and compliance standards

### Prerequisites
- CNI plugin that supports NetworkPolicy (Calico, Cilium, Weave Net, etc.)
- Kubernetes cluster with NetworkPolicy support enabled

## API Specification

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: string
  namespace: string
  labels: {}
  annotations: {}
spec:
  podSelector:                        # Required: Pods this policy applies to
    matchLabels: {}
  policyTypes:                        # Optional: ["Ingress"], ["Egress"], or both
  - Ingress
  - Egress
  ingress:                           # Optional: Ingress rules
  - from:                            # Optional: Source selectors
    - podSelector: {}                # Pods in same namespace
    - namespaceSelector: {}          # Pods in selected namespaces
    - ipBlock:                       # IP CIDR ranges
        cidr: string
        except: []
    ports:                           # Optional: Allowed ports
    - protocol: TCP/UDP/SCTP
      port: int/string
      endPort: int                   # Port range end (1.25+)
  egress:                            # Optional: Egress rules
  - to:                              # Optional: Destination selectors
    - podSelector: {}
    - namespaceSelector: {}
    - ipBlock:
        cidr: string
        except: []
    ports:                           # Optional: Allowed ports
    - protocol: TCP/UDP/SCTP
      port: int/string
      endPort: int
```

## Field Reference

### Metadata Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Name of the NetworkPolicy resource |
| `namespace` | string | Namespace where the NetworkPolicy applies |
| `labels` | map[string]string | Key-value pairs for organizing resources |
| `annotations` | map[string]string | Additional metadata for the resource |

### Spec Fields

#### podSelector (Required)
**Type**: `LabelSelector`  
**Description**: Selects the pods to which this NetworkPolicy applies

```yaml
podSelector:
  matchLabels:
    app: backend
    tier: database
```

**Empty selector** (applies to all pods in namespace):
```yaml
podSelector: {}
```

#### policyTypes
**Type**: `[]string`  
**Options**: `["Ingress"]`, `["Egress"]`, `["Ingress", "Egress"]`  
**Description**: Types of traffic the policy applies to

```yaml
policyTypes:
- Ingress  # Controls incoming traffic
- Egress   # Controls outgoing traffic
```

### Traffic Rules

#### ingress
**Type**: `[]NetworkPolicyIngressRule`  
**Description**: Rules for incoming traffic to selected pods

##### from Selectors

**podSelector**: Select pods in the same namespace
```yaml
ingress:
- from:
  - podSelector:
      matchLabels:
        app: frontend
```

**namespaceSelector**: Select pods from specific namespaces
```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        name: production
```

**ipBlock**: Allow traffic from IP ranges
```yaml
ingress:
- from:
  - ipBlock:
      cidr: 10.0.0.0/8
      except:
      - 10.0.1.0/24  # Exclude this subnet
```

**Combined selectors** (AND logic within rule, OR logic between rules):
```yaml
ingress:
- from:
  - podSelector:
      matchLabels:
        app: frontend
    namespaceSelector:
      matchLabels:
        env: production
```

##### ports
**Type**: `[]NetworkPolicyPort`  
**Description**: Allowed ports and protocols

```yaml
ports:
- protocol: TCP
  port: 80
- protocol: TCP
  port: 443
- protocol: UDP
  port: 53
```

**Port ranges** (Kubernetes 1.25+):
```yaml
ports:
- protocol: TCP
  port: 8080
  endPort: 8090  # Allows ports 8080-8090
```

**Named ports**:
```yaml
ports:
- protocol: TCP
  port: http  # References container's named port
```

#### egress
**Type**: `[]NetworkPolicyEgressRule`  
**Description**: Rules for outgoing traffic from selected pods

Similar structure to ingress rules:
```yaml
egress:
- to:
  - podSelector:
      matchLabels:
        app: database
  ports:
  - protocol: TCP
    port: 5432
```

## Common Use Cases

### 1. Default Deny All Traffic

```yaml
# Deny all ingress traffic to all pods in namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
# Deny all egress traffic from all pods in namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Egress
```

### 2. Allow All Traffic

```yaml
# Allow all ingress traffic to all pods in namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all-ingress
  namespace: development
spec:
  podSelector: {}
  ingress:
  - {}  # Empty rule allows all
  policyTypes:
  - Ingress
---
# Allow all egress traffic from all pods in namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all-egress
  namespace: development
spec:
  podSelector: {}
  egress:
  - {}  # Empty rule allows all
  policyTypes:
  - Egress
```

### 3. Three-Tier Application Isolation

```yaml
# Frontend can only receive traffic from ingress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-netpol
  namespace: webapp
spec:
  podSelector:
    matchLabels:
      tier: frontend
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 80
  egress:
  - to:
    - podSelector:
        matchLabels:
          tier: backend
    ports:
    - protocol: TCP
      port: 8080
---
# Backend can receive from frontend, send to database
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-netpol
  namespace: webapp
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: frontend
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - podSelector:
        matchLabels:
          tier: database
    ports:
    - protocol: TCP
      port: 5432
  # Allow DNS resolution
  - to: {}
    ports:
    - protocol: UDP
      port: 53
---
# Database can only receive from backend
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: database-netpol
  namespace: webapp
spec:
  podSelector:
    matchLabels:
      tier: database
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: backend
    ports:
    - protocol: TCP
      port: 5432
```

### 4. Namespace Isolation

```yaml
# Allow communication within namespace only
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: namespace-isolation
  namespace: team-a
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector: {}  # All pods in same namespace
  egress:
  - to:
    - podSelector: {}  # All pods in same namespace
  # Allow DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

### 5. External Service Access

```yaml
# Allow specific pods to access external APIs
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: external-api-access
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: api-client
  policyTypes:
  - Egress
  egress:
  # Allow access to external API
  - to:
    - ipBlock:
        cidr: 203.0.113.0/24  # External API subnet
    ports:
    - protocol: TCP
      port: 443
  # Allow DNS resolution
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

### 6. Development vs Production Isolation

```yaml
# Production namespace - strict isolation
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: production-isolation
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Only allow from same namespace and ingress
  - from:
    - podSelector: {}
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
  egress:
  # Allow to same namespace
  - to:
    - podSelector: {}
  # Allow to external services
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except:
        - 10.0.0.0/8  # Block internal cluster networks
        - 172.16.0.0/12
        - 192.168.0.0/16
  # Allow DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

### 7. Monitoring and Logging Access

```yaml
# Allow monitoring tools to scrape metrics
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: monitoring-access
  namespace: application
spec:
  podSelector:
    matchLabels:
      monitoring: "true"
  policyTypes:
  - Ingress
  ingress:
  # Allow Prometheus to scrape metrics
  - from:
    - namespaceSelector:
        matchLabels:
          name: monitoring
      podSelector:
        matchLabels:
          app: prometheus
    ports:
    - protocol: TCP
      port: metrics  # Named port
  # Allow logging agents
  - from:
    - namespaceSelector:
        matchLabels:
          name: logging
      podSelector:
        matchLabels:
          app: fluent-bit
```

## Best Practices

### 1. Start with Default Deny
```yaml
# Implement default deny as baseline security
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

### 2. Use Meaningful Labels
```yaml
# Use consistent, descriptive labels
metadata:
  labels:
    policy-type: "security"
    tier: "database"
spec:
  podSelector:
    matchLabels:
      app: postgres
      tier: database
      security-zone: restricted
```

### 3. Include DNS Resolution
```yaml
# Always allow DNS for egress policies
egress:
- to:
  - namespaceSelector:
      matchLabels:
        name: kube-system
  ports:
  - protocol: UDP
    port: 53
```

### 4. Document Policy Intent
```yaml
metadata:
  name: frontend-security-policy
  annotations:
    description: "Allows frontend pods to communicate with backend and receive traffic from ingress"
    policy-version: "v1.2"
    last-updated: "2024-01-15"
```

### 5. Test Gradually
```yaml
# Use annotations to track testing
metadata:
  annotations:
    policy-status: "testing"
    test-date: "2024-01-15"
    tested-scenarios: "frontend-to-backend,ingress-to-frontend"
```

## Troubleshooting

### Common Issues

#### 1. Policy Not Taking Effect
```bash
# Check if CNI supports NetworkPolicy
kubectl get nodes -o wide

# Verify NetworkPolicy exists
kubectl get networkpolicy -A

# Check policy details
kubectl describe networkpolicy my-policy

# Test connectivity
kubectl run test-pod --image=busybox --rm -it -- nc -zv target-service 80
```

#### 2. DNS Resolution Failures
```bash
# Check if DNS is allowed in egress rules
kubectl get networkpolicy my-policy -o yaml | grep -A 10 egress

# Test DNS resolution
kubectl run dns-test --image=busybox --rm -it -- nslookup kubernetes.default.svc.cluster.local

# Check kube-dns/CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

#### 3. Unexpected Traffic Blocking
```bash
# Check all policies affecting a pod
kubectl get networkpolicy -o wide

# Describe pod to see labels
kubectl describe pod my-pod

# Check policy selectors
kubectl get networkpolicy -o yaml | grep -A 5 podSelector

# Verify namespace labels
kubectl get namespace --show-labels
```

### Debugging Commands

```bash
# List all NetworkPolicies
kubectl get networkpolicy -A

# Get policy details
kubectl describe networkpolicy my-policy

# Check policy YAML
kubectl get networkpolicy my-policy -o yaml

# Test connectivity between pods
kubectl run test-source --image=busybox --rm -it -- nc -zv target-pod-ip 8080

# Check pod labels
kubectl get pods --show-labels

# Check namespace labels
kubectl get namespaces --show-labels

# View CNI logs (depends on CNI plugin)
kubectl logs -n kube-system -l k8s-app=calico-node

# Test with curl
kubectl run curl-test --image=curlimages/curl --rm -it -- curl -m 5 http://target-service:80
```

### Testing NetworkPolicies

```bash
# Create test namespace
kubectl create namespace netpol-test

# Apply default deny policy
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: netpol-test
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF

# Create test pods
kubectl run server --image=nginx -n netpol-test
kubectl run client --image=busybox -n netpol-test --rm -it -- wget -qO- --timeout=2 server

# Should fail due to default deny

# Apply allow policy
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-client-to-server
  namespace: netpol-test
spec:
  podSelector:
    matchLabels:
      run: server
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          run: client
EOF

# Test again - should succeed
kubectl run client --image=busybox -n netpol-test --rm -it -- wget -qO- --timeout=2 server
```

## Examples by Scenario

### Development Environment (Permissive)
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: dev-allow-all
  namespace: development
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - {}
  egress:
  - {}
```

### Staging Environment (Moderate)
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: staging-controlled
  namespace: staging
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector: {}
    - namespaceSelector:
        matchLabels:
          env: staging
  egress:
  - to:
    - podSelector: {}
  - to: {}
    ports:
    - protocol: TCP
      port: 443
    - protocol: UDP
      port: 53
```

### Production Environment (Restrictive)
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: production-strict
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  # Default deny - specific allow rules defined per service
```

---

## References

- [Kubernetes Official Documentation: Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Kubernetes API Reference: NetworkPolicy](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.28/#networkpolicy-v1-networking-k8s-io)
- [Network Policy Recipes](https://github.com/ahmetb/kubernetes-network-policy-recipes)
- [Calico Network Policy Tutorial](https://docs.projectcalico.org/security/tutorials/kubernetes-policy-basic)
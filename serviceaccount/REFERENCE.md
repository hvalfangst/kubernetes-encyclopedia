# Kubernetes ServiceAccount Resource Documentation

## Table of Contents
- [Overview](#overview)
- [API Specification](#api-specification)
- [Field Reference](#field-reference)
- [RBAC Integration](#rbac-integration)
- [Token Management](#token-management)
- [Common Use Cases](#common-use-cases)
- [Best Practices](#best-practices)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

## Overview

A **ServiceAccount** provides an identity for processes that run in a Pod. When you create a pod, if you do not specify a service account, it is automatically assigned the `default` service account in the same namespace. ServiceAccounts are used to control what API operations pods can perform.

### Key Features
- Pod identity and authentication to Kubernetes API
- Integration with Role-Based Access Control (RBAC)
- Automatic token provisioning and mounting
- Namespace-scoped identity management
- Support for external identity providers (OIDC, etc.)
- Image pull secrets association

### When to Use ServiceAccounts
- **Application API access**: Apps that need to interact with Kubernetes API
- **CI/CD pipelines**: Automated deployment and management tools
- **Monitoring systems**: Tools that need to read cluster state
- **Security enforcement**: Applications requiring specific permissions
- **Custom controllers**: Applications that manage Kubernetes resources
- **Service mesh**: Identity for inter-service communication

## API Specification

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: string
  namespace: string
  labels: {}
  annotations: {}
  finalizers: []
secrets:                              # Optional: Manual secret references
- name: string
imagePullSecrets:                     # Optional: Secrets for pulling images
- name: string
automountServiceAccountToken: boolean # Optional: Auto-mount API token
```

## Field Reference

### Metadata Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Name of the ServiceAccount |
| `namespace` | string | Namespace where the ServiceAccount resides |
| `labels` | map[string]string | Key-value pairs for organizing resources |
| `annotations` | map[string]string | Additional metadata and configuration |
| `finalizers` | []string | List of finalizers for cleanup operations |

### Spec Fields

#### secrets
**Type**: `[]ObjectReference`  
**Description**: List of secrets allowed to be used by pods running using this ServiceAccount

```yaml
secrets:
- name: my-secret
- name: another-secret
```

**Note**: In Kubernetes 1.24+, secrets are no longer automatically created for ServiceAccounts. Use TokenRequest API or manual secret creation.

#### imagePullSecrets
**Type**: `[]LocalObjectReference`  
**Description**: List of secrets containing credentials for pulling container images

```yaml
imagePullSecrets:
- name: registry-secret
- name: private-registry-creds
```

#### automountServiceAccountToken
**Type**: `boolean`  
**Default**: `true`  
**Description**: Controls whether the service account token is automatically mounted in pods

```yaml
automountServiceAccountToken: false  # Disable auto-mounting
```

### Annotations

#### Common ServiceAccount Annotations

| Annotation | Description |
|------------|-------------|
| `kubernetes.io/service-account.name` | ServiceAccount name (set by system) |
| `kubernetes.io/service-account.uid` | ServiceAccount UID (set by system) |
| `eks.amazonaws.com/role-arn` | AWS IAM role for IRSA (EKS) |
| `iam.gke.io/gcp-service-account` | GCP service account for Workload Identity (GKE) |

## RBAC Integration

ServiceAccounts work closely with RBAC to define permissions:

### Role-Based Access Control Flow
1. **ServiceAccount**: Provides identity
2. **Role/ClusterRole**: Defines permissions
3. **RoleBinding/ClusterRoleBinding**: Connects identity to permissions

### Basic RBAC Example

```yaml
# ServiceAccount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pod-reader
  namespace: default
---
# Role defining permissions
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader-role
  namespace: default
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
---
# RoleBinding connecting ServiceAccount to Role
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-binding
  namespace: default
subjects:
- kind: ServiceAccount
  name: pod-reader
  namespace: default
roleRef:
  kind: Role
  name: pod-reader-role
  apiGroup: rbac.authorization.k8s.io
```

## Token Management

### Kubernetes 1.24+ Token Management

Starting with Kubernetes 1.24, ServiceAccount tokens are no longer automatically created as secrets. Instead, use:

#### TokenRequest API (Recommended)
```yaml
# Pod using projected volume for token
apiVersion: v1
kind: Pod
metadata:
  name: token-example
spec:
  serviceAccountName: my-serviceaccount
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: token
      mountPath: /var/run/secrets/tokens
  volumes:
  - name: token
    projected:
      sources:
      - serviceAccountToken:
          path: token
          expirationSeconds: 3600  # 1 hour
          audience: api
```

#### Manual Token Secret Creation
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-serviceaccount-token
  annotations:
    kubernetes.io/service-account.name: my-serviceaccount
type: kubernetes.io/service-account-token
```

### Legacy Token Management (Pre-1.24)

```yaml
# ServiceAccount with automatic secret creation
apiVersion: v1
kind: ServiceAccount
metadata:
  name: legacy-account
secrets:
- name: legacy-account-token-xyz12  # Auto-created
```

## Common Use Cases

### 1. Application with API Access

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-api-client
  namespace: production
  labels:
    app: my-application
    component: api-client
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-api-role
  namespace: production
rules:
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-api-binding
  namespace: production
subjects:
- kind: ServiceAccount
  name: app-api-client
  namespace: production
roleRef:
  kind: Role
  name: app-api-role
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-client-app
  namespace: production
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-client
  template:
    metadata:
      labels:
        app: api-client
    spec:
      serviceAccountName: app-api-client
      containers:
      - name: app
        image: my-app:v1.0.0
        env:
        - name: KUBERNETES_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
```

### 2. CI/CD Pipeline ServiceAccount

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ci-cd-deployer
  namespace: ci-cd
  labels:
    purpose: deployment
    team: platform
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ci-cd-deployer-role
rules:
# Deployment permissions
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
# Service permissions
- apiGroups: [""]
  resources: ["services"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
# ConfigMap and Secret permissions
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
# Ingress permissions
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ci-cd-deployer-binding
subjects:
- kind: ServiceAccount
  name: ci-cd-deployer
  namespace: ci-cd
roleRef:
  kind: ClusterRole
  name: ci-cd-deployer-role
  apiGroup: rbac.authorization.k8s.io
```

### 3. Monitoring ServiceAccount

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus-server
  namespace: monitoring
  labels:
    app: prometheus
    component: server
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus-server-role
rules:
- apiGroups: [""]
  resources: ["nodes", "nodes/metrics", "services", "endpoints", "pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get"]
- nonResourceURLs: ["/metrics"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus-server-binding
subjects:
- kind: ServiceAccount
  name: prometheus-server
  namespace: monitoring
roleRef:
  kind: ClusterRole
  name: prometheus-server-role
  apiGroup: rbac.authorization.k8s.io
```

### 4. ServiceAccount with Image Pull Secrets

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: private-registry-secret
  namespace: production
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: ewogICJhdXRocyI6IHsKICAgICJyZWdpc3RyeS5leGFtcGxlLmNvbSI6IHsKICAgICAgInVzZXJuYW1lIjogInVzZXIiLAogICAgICAicGFzc3dvcmQiOiAicGFzcyIsCiAgICAgICJhdXRoIjogImRYTmxjanB3WVhOeiIKICAgIH0KICB9Cn0=
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: private-registry-user
  namespace: production
imagePullSecrets:
- name: private-registry-secret
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: private-app
  namespace: production
spec:
  replicas: 1
  selector:
    matchLabels:
      app: private-app
  template:
    metadata:
      labels:
        app: private-app
    spec:
      serviceAccountName: private-registry-user
      containers:
      - name: app
        image: registry.example.com/private/app:v1.0.0
```

### 5. Security-Focused ServiceAccount

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: security-scanner
  namespace: security
  labels:
    purpose: security-scanning
  annotations:
    description: "ServiceAccount for security scanning tools"
automountServiceAccountToken: false  # Disable auto-mounting for security
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: security-scanner-role
rules:
# Read-only access to security-relevant resources
- apiGroups: [""]
  resources: ["pods", "services", "configmaps"]
  verbs: ["get", "list"]
- apiGroups: ["apps"]
  resources: ["deployments", "daemonsets", "statefulsets"]
  verbs: ["get", "list"]
- apiGroups: ["networking.k8s.io"]
  resources: ["networkpolicies"]
  verbs: ["get", "list"]
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: security-scanner-binding
subjects:
- kind: ServiceAccount
  name: security-scanner
  namespace: security
roleRef:
  kind: ClusterRole
  name: security-scanner-role
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: Pod
metadata:
  name: security-scanner-pod
  namespace: security
spec:
  serviceAccountName: security-scanner
  automountServiceAccountToken: false  # Pod-level override
  containers:
  - name: scanner
    image: security-scanner:v2.1.0
    volumeMounts:
    - name: token
      mountPath: /var/run/secrets/tokens
      readOnly: true
  volumes:
  - name: token
    projected:
      sources:
      - serviceAccountToken:
          path: token
          expirationSeconds: 1800  # 30 minutes
```

### 6. Cross-Namespace Access

```yaml
# ServiceAccount in namespace-a
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cross-namespace-client
  namespace: namespace-a
---
# ClusterRole for cross-namespace access
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cross-namespace-role
rules:
- apiGroups: [""]
  resources: ["services", "endpoints"]
  verbs: ["get", "list"]
  resourceNames: []
---
# ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cross-namespace-binding
subjects:
- kind: ServiceAccount
  name: cross-namespace-client
  namespace: namespace-a
roleRef:
  kind: ClusterRole
  name: cross-namespace-role
  apiGroup: rbac.authorization.k8s.io
```

## Best Practices

### 1. Principle of Least Privilege
```yaml
# BAD: Overly broad permissions
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]

# GOOD: Specific permissions
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list"]
  resourceNames: ["app-config"]  # Even more specific
```

### 2. Use Meaningful Names and Labels
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: payment-service-api-client  # Descriptive name
  namespace: payment
  labels:
    app: payment-service
    component: api-client
    team: payments-team
    environment: production
  annotations:
    description: "API client for payment service to read configurations"
    created-by: "payments-team"
    last-reviewed: "2024-01-15"
```

### 3. Namespace-Specific ServiceAccounts
```yaml
# Create per-namespace ServiceAccounts
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-serviceaccount
  namespace: production  # Environment-specific
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-serviceaccount
  namespace: staging     # Same name, different namespace
```

### 4. Token Security
```yaml
# Use short-lived tokens
volumes:
- name: token
  projected:
    sources:
    - serviceAccountToken:
        path: token
        expirationSeconds: 3600  # 1 hour expiry
        audience: api

# Disable auto-mounting when not needed
automountServiceAccountToken: false
```

### 5. Regular Auditing
```yaml
metadata:
  annotations:
    audit.k8s.io/last-review: "2024-01-15"
    audit.k8s.io/reviewer: "security-team"
    audit.k8s.io/next-review: "2024-04-15"
```

## Troubleshooting

### Common Issues

#### 1. Permission Denied Errors
```bash
# Check ServiceAccount permissions
kubectl auth can-i get pods --as=system:serviceaccount:default:my-serviceaccount

# List effective permissions
kubectl describe clusterrolebinding | grep my-serviceaccount
kubectl describe rolebinding -n my-namespace | grep my-serviceaccount

# Check RBAC resources
kubectl get clusterrole,role -A | grep my-role
kubectl get clusterrolebinding,rolebinding -A | grep my-serviceaccount
```

#### 2. Token Mount Issues
```bash
# Check if token is mounted
kubectl exec my-pod -- ls -la /var/run/secrets/kubernetes.io/serviceaccount/

# Check token content
kubectl exec my-pod -- cat /var/run/secrets/kubernetes.io/serviceaccount/token

# Verify ServiceAccount exists
kubectl get serviceaccount my-serviceaccount -n my-namespace

# Check pod ServiceAccount assignment
kubectl get pod my-pod -o jsonpath='{.spec.serviceAccountName}'
```

#### 3. Image Pull Issues
```bash
# Check image pull secrets
kubectl get serviceaccount my-serviceaccount -o yaml | grep imagePullSecrets

# Verify secret exists and is correct type
kubectl get secret my-registry-secret -o yaml

# Check secret is properly formatted
kubectl get secret my-registry-secret -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d
```

### Debugging Commands

```bash
# List all ServiceAccounts
kubectl get serviceaccounts -A

# Get ServiceAccount details
kubectl describe serviceaccount my-serviceaccount -n my-namespace

# Check ServiceAccount YAML
kubectl get serviceaccount my-serviceaccount -n my-namespace -o yaml

# List tokens associated with ServiceAccount (legacy)
kubectl get secrets -o json | jq -r '.items[] | select(.metadata.annotations."kubernetes.io/service-account.name"=="my-serviceaccount") | .metadata.name'

# Check RBAC permissions
kubectl auth can-i --list --as=system:serviceaccount:my-namespace:my-serviceaccount

# Get effective ClusterRoleBindings
kubectl get clusterrolebinding -o wide | grep my-serviceaccount

# Get effective RoleBindings
kubectl get rolebinding -A -o wide | grep my-serviceaccount

# Test API access from pod
kubectl exec my-pod -- wget -qO- --header="Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/api/v1/namespaces/default/pods

# Create test token for ServiceAccount
kubectl create token my-serviceaccount -n my-namespace --duration=1h
```

### ServiceAccount Security Checklist

```bash
# 1. Check for overly permissive roles
kubectl get clusterrole -o yaml | grep -A 10 "apiGroups.*\*"

# 2. Find ServiceAccounts with cluster-admin
kubectl get clusterrolebinding -o json | jq -r '.items[] | select(.roleRef.name=="cluster-admin") | .subjects[]? | select(.kind=="ServiceAccount") | "\(.namespace)/\(.name)"'

# 3. List ServiceAccounts with automount enabled
kubectl get serviceaccount -A -o json | jq -r '.items[] | select(.automountServiceAccountToken != false) | "\(.metadata.namespace)/\(.metadata.name)"'

# 4. Check for unused ServiceAccounts
for sa in $(kubectl get serviceaccount -A -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}'); do
  ns=$(echo $sa | cut -d' ' -f1)
  name=$(echo $sa | cut -d' ' -f2)
  if ! kubectl get pods -A --field-selector=spec.serviceAccountName=$name -o name | grep -q .; then
    echo "Unused ServiceAccount: $ns/$name"
  fi
done
```

## Cloud Provider Integration

### AWS EKS - IAM Roles for Service Accounts (IRSA)

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-service-account
  namespace: default
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/MyRole
```

### Google GKE - Workload Identity

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gcp-service-account
  namespace: default
  annotations:
    iam.gke.io/gcp-service-account: my-gcp-sa@my-project.iam.gserviceaccount.com
```

### Azure AKS - Azure AD Workload Identity

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: azure-service-account
  namespace: default
  annotations:
    azure.workload.identity/client-id: "12345678-1234-1234-1234-123456789012"
  labels:
    azure.workload.identity/use: "true"
```

---

## References

- [Kubernetes Official Documentation: ServiceAccounts](https://kubernetes.io/docs/concepts/security/service-accounts/)
- [Kubernetes API Reference: ServiceAccount](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.28/#serviceaccount-v1-core)
- [RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Managing Service Accounts](https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/)
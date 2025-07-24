# Kubernetes Secret Resource Documentation

## Table of Contents
- [Overview](#overview)
- [API Specification](#api-specification)
- [Field Reference](#field-reference)
- [Secret Types](#secret-types)
- [Security Considerations](#security-considerations)
- [Usage Patterns](#usage-patterns)
- [Common Use Cases](#common-use-cases)
- [Best Practices](#best-practices)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

## Overview

A **Secret** stores sensitive data like passwords, tokens, and keys, providing a mechanism to separate confidential data from application code and reduce risk of accidental exposure.

### Key Features
- Secure storage of sensitive information
- Base64 encoding for data protection
- Integration with Pod environment variables
- Volume mounting for file-based secrets
- Support for multiple secret types
- Encryption at rest capabilities
- RBAC integration for access control

### When to Use Secrets
- **Database credentials**: Store passwords and connection strings
- **API tokens**: Secure external service authentication
- **TLS certificates**: SSL/TLS keys and certificates
- **SSH keys**: Private keys for secure connections
- **Docker registry credentials**: Private image access
- **OAuth tokens**: Authentication tokens for services

## API Specification

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: string
  namespace: string
  labels: {}
  annotations: {}
type: string                         # Secret type (Opaque, ServiceAccount, etc.)
data:                               # Base64 encoded data
  key1: <base64-string>
  key2: <base64-string>
stringData:                         # Plain text data (converted to base64)
  key3: "plain-text-value"
  key4: "another-plain-value"
immutable: boolean                  # Make Secret immutable (optional)
```

## Field Reference

### Metadata Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Name of the Secret resource |
| `namespace` | string | Namespace where the Secret resides |
| `labels` | map[string]string | Key-value pairs for organizing resources |
| `annotations` | map[string]string | Additional metadata for the resource |

### Spec Fields

#### type
**Type**: `string`  
**Default**: `Opaque`  
**Description**: Type of secret data

**Secret Types**:
- `Opaque`: Arbitrary user-defined data
- `kubernetes.io/service-account-token`: Service account token
- `kubernetes.io/dockercfg`: Docker registry credentials (legacy)
- `kubernetes.io/dockerconfigjson`: Docker registry credentials
- `kubernetes.io/basic-auth`: Basic authentication credentials
- `kubernetes.io/ssh-auth`: SSH authentication credentials
- `kubernetes.io/tls`: TLS certificate and key

#### data
**Type**: `map[string][]byte`  
**Description**: Base64 encoded secret data

```yaml
data:
  username: YWRtaW4=     # base64 encoded "admin"
  password: cGFzc3dvcmQ= # base64 encoded "password"
```

#### stringData
**Type**: `map[string]string`  
**Description**: Plain text data (automatically base64 encoded)

```yaml
stringData:
  username: "admin"
  password: "password"
  config.yaml: |
    database:
      host: postgres.example.com
      port: 5432
```

#### immutable
**Type**: `boolean`  
**Default**: `false`  
**Description**: Prevents updates to the Secret

```yaml
immutable: true  # Secret cannot be modified
```

## Secret Types

### Opaque Secrets

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
type: Opaque
stringData:
  username: "dbuser"
  password: "dbpassword123"
  database-url: "postgresql://dbuser:dbpassword123@postgres:5432/mydb"
```

### TLS Secrets

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: tls-secret
type: kubernetes.io/tls
data:
  tls.crt: LS0tLS1CRUdJTi... # Base64 encoded certificate
  tls.key: LS0tLS1CRUdJTi... # Base64 encoded private key
```

### Docker Registry Secrets

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: registry-secret
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: eyJhdXRocyI6eyJyZWdpc3RyeS5leGFtcGxlLmNvbSI6eyJ1c2VybmFtZSI6InVzZXIiLCJwYXNzd29yZCI6InBhc3MiLCJhdXRoIjoiZFhObGNqcHdZWE56In19fQ==
```

### Basic Auth Secrets

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: basic-auth-secret
type: kubernetes.io/basic-auth
stringData:
  username: "admin"
  password: "secretpassword"
```

### SSH Auth Secrets

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ssh-secret
type: kubernetes.io/ssh-auth
data:
  ssh-privatekey: LS0tLS1CRUdJTi... # Base64 encoded SSH private key
```

## Security Considerations

### Encryption at Rest

```yaml
# Enable encryption at rest in kube-apiserver
apiVersion: apiserver.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: <32-byte-key>
  - identity: {}
```

### RBAC Configuration

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: secret-reader
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list"]
  resourceNames: ["specific-secret"]  # Limit to specific secrets
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: secret-reader-binding
subjects:
- kind: ServiceAccount
  name: app-service-account
  namespace: default
roleRef:
  kind: Role
  name: secret-reader
  apiGroup: rbac.authorization.k8s.io
```

### Pod Security Standards

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
spec:
  serviceAccountName: limited-service-account
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 2000
  containers:
  - name: app
    image: myapp:latest
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      runAsNonRoot: true
      capabilities:
        drop:
        - ALL
    env:
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-secret
          key: password
```

## Usage Patterns

### Environment Variables

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: env-pod
spec:
  containers:
  - name: app
    image: myapp:latest
    env:
    # Single environment variable from Secret
    - name: DATABASE_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-secret
          key: password
    # All keys as environment variables
    envFrom:
    - secretRef:
        name: app-secrets
```

### Volume Mounts

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: volume-pod
spec:
  containers:
  - name: app
    image: myapp:latest
    volumeMounts:
    # Mount entire Secret as files
    - name: secret-volume
      mountPath: /etc/secrets
      readOnly: true
    # Mount specific key as file
    - name: tls-volume
      mountPath: /etc/ssl/certs/tls.crt
      subPath: tls.crt
      readOnly: true
  volumes:
  - name: secret-volume
    secret:
      secretName: app-secrets
      defaultMode: 0400  # Read-only for owner
  - name: tls-volume
    secret:
      secretName: tls-secret
      items:
      - key: tls.crt
        path: tls.crt
        mode: 0444
```

### Image Pull Secrets

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: private-image-pod
spec:
  imagePullSecrets:
  - name: registry-secret
  containers:
  - name: app
    image: private-registry.example.com/myapp:latest
```

## Common Use Cases

### Database Credentials

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
  labels:
    app: postgres
type: Opaque
stringData:
  # Connection details
  postgres-user: "appuser"
  postgres-password: "securepassword123"
  postgres-db: "application_db"
  
  # Connection URL
  database-url: "postgresql://appuser:securepassword123@postgres:5432/application_db"
  
  # SSL configuration
  sslmode: "require"
  
  # Connection pool settings
  max-connections: "20"
  connection-timeout: "30"
---
# Usage in Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-deployment
spec:
  template:
    spec:
      containers:
      - name: app
        image: myapp:latest
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: database-url
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: postgres-user
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: postgres-password
```

### API Keys and Tokens

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: api-keys
  labels:
    component: external-integrations
type: Opaque
stringData:
  # Third-party API keys
  stripe-api-key: "sk_live_..."
  sendgrid-api-key: "SG...."
  aws-access-key-id: "AKIA..."
  aws-secret-access-key: "..."
  
  # OAuth tokens
  github-token: "ghp_..."
  google-oauth-client-id: "..."
  google-oauth-client-secret: "..."
  
  # JWT secrets
  jwt-secret: "your-256-bit-secret"
  refresh-token-secret: "your-refresh-secret"
  
  # Webhook secrets
  webhook-secret: "webhook-signing-secret"
```

### TLS Certificates

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: webapp-tls
  labels:
    app: webapp
type: kubernetes.io/tls
data:
  # Certificate chain (base64 encoded)
  tls.crt: |
    LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t
    MIIDXTCCAkWgAwIBAgIJAKL7...
    LS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQ==
  
  # Private key (base64 encoded)
  tls.key: |
    LS0tLS1CRUdJTiBQUklWQVRFIEtFWS0tLS0t
    MIIEvQIBADANBgkqhkiG9w0B...
    LS0tLS1FTkQgUFJJVkFURSBLRVktLS0tLQ==
---
# Usage in Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: webapp-ingress
spec:
  tls:
  - hosts:
    - webapp.example.com
    secretName: webapp-tls
  rules:
  - host: webapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: webapp-service
            port:
              number: 80
```

### SSH Keys

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: git-ssh-secret
type: kubernetes.io/ssh-auth
stringData:
  ssh-privatekey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAFwAAAAdzc2gtcn
    ...
    -----END OPENSSH PRIVATE KEY-----
---
# Usage in Pod for Git operations
apiVersion: v1
kind: Pod
metadata:
  name: git-clone-pod
spec:
  containers:
  - name: git-clone
    image: alpine/git
    command: ['sh', '-c']
    args:
    - |
      mkdir -p ~/.ssh
      cp /etc/ssh-key/ssh-privatekey ~/.ssh/id_rsa
      chmod 600 ~/.ssh/id_rsa
      ssh-keyscan github.com >> ~/.ssh/known_hosts
      git clone git@github.com:user/private-repo.git /workspace
    volumeMounts:
    - name: ssh-key
      mountPath: /etc/ssh-key
      readOnly: true
  volumes:
  - name: ssh-key
    secret:
      secretName: git-ssh-secret
      defaultMode: 0400
```

## Best Practices

### Secret Management

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: secure-app-secrets
  labels:
    app.kubernetes.io/name: myapp
    app.kubernetes.io/instance: production
    app.kubernetes.io/version: "1.0.0"
    app.kubernetes.io/component: secrets
    app.kubernetes.io/managed-by: external-secrets-operator
  annotations:
    # Secret source and rotation info
    secrets.kubernetes.io/source: "aws-secrets-manager"
    secrets.kubernetes.io/rotation-schedule: "0 2 * * 0"  # Weekly
    secrets.kubernetes.io/last-rotated: "2023-10-01T02:00:00Z"
type: Opaque
stringData:
  # Short-lived credentials
  database-password: "rotated-weekly-password"
  api-token: "short-lived-token"
  
  # Version secrets for blue-green deployments
  config-version: "v1.2.3"
immutable: false  # Allow rotation
```

### Least Privilege Access

```yaml
# Service Account with minimal permissions
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-service-account
---
# Role with specific secret access
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: app-secrets-reader
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get"]
  resourceNames: ["app-database-secret", "app-api-keys"]  # Specific secrets only
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-secrets-binding
subjects:
- kind: ServiceAccount
  name: app-service-account
roleRef:
  kind: Role
  name: app-secrets-reader
  apiGroup: rbac.authorization.k8s.io
```

### External Secret Management

```yaml
# Using External Secrets Operator
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: vault-secret
spec:
  refreshInterval: 15s
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: myapp-secret
    creationPolicy: Owner
  data:
  - secretKey: password
    remoteRef:
      key: secret/myapp
      property: password
---
# SecretStore configuration
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "myapp-role"
```

## Troubleshooting

### Common Issues

#### 1. Secret Not Found

```bash
# Check if Secret exists
kubectl get secret mysecret -o wide

# List all secrets
kubectl get secrets

# Check in specific namespace
kubectl get secret mysecret -n mynamespace

# Verify Secret content
kubectl describe secret mysecret
kubectl get secret mysecret -o yaml
```

#### 2. Base64 Encoding Issues

```bash
# Decode secret values
kubectl get secret mysecret -o jsonpath='{.data.password}' | base64 -d

# Check for encoding issues
kubectl get secret mysecret -o jsonpath='{.data}' | jq -r 'to_entries[] | "\(.key): \(.value | @base64d)"'

# Validate stringData vs data
kubectl get secret mysecret -o yaml | grep -A 10 -E "(data|stringData):"
```

#### 3. Pod Not Using Secret

```bash
# Check Pod environment variables
kubectl exec mypod -- env | grep SECRET

# Check mounted secret files
kubectl exec mypod -- ls -la /etc/secrets/
kubectl exec mypod -- cat /etc/secrets/password

# Verify Pod specification
kubectl get pod mypod -o yaml | grep -A 20 -E "(env|volumes)"

# Check for RBAC issues
kubectl auth can-i get secrets --as=system:serviceaccount:default:myapp
```

### Debugging Commands

```bash
# List all secrets
kubectl get secrets
kubectl get secrets --all-namespaces

# Get secret details
kubectl describe secret mysecret

# View secret data (decoded)
kubectl get secret mysecret -o jsonpath='{.data}' | jq -r 'to_entries[] | "\(.key): \(.value | @base64d)"'

# Create secret from command line
kubectl create secret generic mysecret --from-literal=username=admin --from-literal=password=secret

# Create TLS secret from files
kubectl create secret tls tls-secret --cert=tls.crt --key=tls.key

# Create Docker registry secret
kubectl create secret docker-registry registry-secret \
  --docker-server=registry.example.com \
  --docker-username=user \
  --docker-password=pass \
  --docker-email=user@example.com

# Update secret
kubectl patch secret mysecret -p '{"stringData":{"newkey":"newvalue"}}'

# Export secret to file
kubectl get secret mysecret -o yaml > mysecret.yaml

# Test secret in temporary pod
kubectl run test-pod --image=busybox --rm -it --restart=Never \
  --env="SECRET_VALUE" --env-from="secretRef:name=mysecret" \
  -- env | grep SECRET
```

### Security Validation

```bash
# Check secret permissions
kubectl auth can-i get secrets
kubectl auth can-i list secrets

# Verify encryption at rest
kubectl get secrets -o yaml | grep -q "k8s:enc:" && echo "Encrypted" || echo "Not encrypted"

# Check secret usage in pods
kubectl get pods -o yaml | grep -A 5 -B 5 secretKeyRef

# Audit secret access
kubectl get events --field-selector reason=SecretMounted
kubectl get events --field-selector involvedObject.kind=Secret

# Validate RBAC configuration
kubectl describe role secret-reader
kubectl describe rolebinding secret-reader-binding
```

---

## References

- [Kubernetes Official Documentation: Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Kubernetes API Reference: Secret](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.28/#secret-v1-core)
- [Managing Secrets in Kubernetes](https://kubernetes.io/docs/tasks/configmap-secret/)
- [External Secrets Operator](https://external-secrets.io/)
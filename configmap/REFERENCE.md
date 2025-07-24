# Kubernetes ConfigMap Resource Documentation

## Table of Contents
- [Overview](#overview)
- [API Specification](#api-specification)
- [Field Reference](#field-reference)
- [Data Types](#data-types)
- [Usage Patterns](#usage-patterns)
- [Common Use Cases](#common-use-cases)
- [Best Practices](#best-practices)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

## Overview

A **ConfigMap** stores non-confidential configuration data in key-value pairs, allowing decoupling of environment-specific configuration from container images.

### Key Features
- Store configuration data separately from application code
- Mount configuration files as volumes
- Set environment variables from configuration data
- Support for UTF-8 strings and binary data
- Immutable ConfigMaps for performance and consistency
- Automatic updates when mounted as volumes

### When to Use ConfigMaps
- **Application configuration**: Store app settings and parameters
- **Configuration files**: Mount config files into containers
- **Environment variables**: Set container environment from config
- **Command arguments**: Configure container commands
- **Feature flags**: Control application behavior
- **Database connections**: Store connection strings and settings

## API Specification

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: string
  namespace: string
  labels: {}
  annotations: {}
data:                                 # UTF-8 string data
  key1: "value1"
  key2: |
    multi-line
    content
binaryData:                          # Binary data (base64 encoded)
  binary-key: <base64-encoded-data>
immutable: boolean                   # Make ConfigMap immutable (optional)
```

## Field Reference

### Metadata Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Name of the ConfigMap resource |
| `namespace` | string | Namespace where the ConfigMap resides |
| `labels` | map[string]string | Key-value pairs for organizing resources |
| `annotations` | map[string]string | Additional metadata for the resource |

### Spec Fields

#### data
**Type**: `map[string]string`  
**Description**: UTF-8 string key-value pairs

```yaml
data:
  database_url: "postgresql://user:password@host:5432/db"
  log_level: "info"
  config.yaml: |
    server:
      port: 8080
      host: 0.0.0.0
    database:
      host: postgres
      port: 5432
```

#### binaryData
**Type**: `map[string][]byte`  
**Description**: Binary data as base64-encoded strings

```yaml
binaryData:
  ssl_cert: LS0tLS1CRUdJTi...  # Base64 encoded certificate
  image_data: iVBORw0KGgoAAAA... # Base64 encoded image
```

#### immutable
**Type**: `boolean`  
**Default**: `false`  
**Description**: Prevents updates to the ConfigMap

```yaml
immutable: true  # ConfigMap cannot be updated
```

**Benefits of Immutable ConfigMaps**:
- Performance: No watches needed by kubelet
- Consistency: Prevents accidental changes
- Reliability: Guaranteed configuration integrity

## Data Types

### Simple Key-Value Pairs

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: simple-config
data:
  environment: "production"
  debug: "false"
  max_connections: "100"
  timeout: "30s"
```

### Multi-line Configuration Files

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-files
data:
  nginx.conf: |
    server {
        listen 80;
        server_name example.com;
        
        location / {
            proxy_pass http://backend;
            proxy_set_header Host $host;
        }
    }
  app.properties: |
    # Application Properties
    app.name=MyApplication
    app.version=1.0.0
    database.url=jdbc:postgresql://postgres:5432/mydb
    logging.level=INFO
  config.json: |
    {
      "api": {
        "endpoint": "https://api.example.com",
        "timeout": 5000,
        "retries": 3
      },
      "features": {
        "feature_a": true,
        "feature_b": false
      }
    }
```

### Binary Data

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: binary-config
binaryData:
  # Base64 encoded certificate
  ca.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...
  # Base64 encoded image
  logo.png: iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB...
data:
  # Regular string data can coexist
  description: "Contains binary certificate and logo"
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
    # Single environment variable from ConfigMap
    - name: DATABASE_URL
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: database_url
    # All keys as environment variables
    envFrom:
    - configMapRef:
        name: app-config
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
    # Mount entire ConfigMap as files
    - name: config-volume
      mountPath: /etc/config
      readOnly: true
    # Mount specific key as file
    - name: nginx-config
      mountPath: /etc/nginx/nginx.conf
      subPath: nginx.conf
      readOnly: true
  volumes:
  - name: config-volume
    configMap:
      name: app-config
  - name: nginx-config
    configMap:
      name: nginx-config
      items:
      - key: nginx.conf
        path: nginx.conf
```

### Command Arguments

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: command-pod
spec:
  containers:
  - name: app
    image: myapp:latest
    command: ["myapp"]
    args:
    - "--config=/etc/config/app.yaml"
    - "--log-level=$(LOG_LEVEL)"
    env:
    - name: LOG_LEVEL
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: log_level
    volumeMounts:
    - name: config
      mountPath: /etc/config
  volumes:
  - name: config
    configMap:
      name: app-config
```

## Common Use Cases

### Application Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: webapp-config
  labels:
    app: webapp
data:
  # Database configuration
  database_host: "postgres.example.com"
  database_port: "5432"
  database_name: "webapp_db"
  
  # Redis configuration
  redis_host: "redis.example.com"
  redis_port: "6379"
  
  # Application settings
  log_level: "info"
  debug_mode: "false"
  max_upload_size: "10MB"
  session_timeout: "3600"
  
  # Feature flags
  enable_analytics: "true"
  enable_chat: "false"
  maintenance_mode: "false"
```

### Configuration Files

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  nginx.conf: |
    user nginx;
    worker_processes auto;
    error_log /var/log/nginx/error.log;
    pid /run/nginx.pid;
    
    events {
        worker_connections 1024;
    }
    
    http {
        log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                        '$status $body_bytes_sent "$http_referer" '
                        '"$http_user_agent" "$http_x_forwarded_for"';
        
        access_log /var/log/nginx/access.log main;
        sendfile on;
        tcp_nopush on;
        tcp_nodelay on;
        keepalive_timeout 65;
        types_hash_max_size 2048;
        
        include /etc/nginx/mime.types;
        default_type application/octet-stream;
        
        upstream backend {
            server backend1:8080;
            server backend2:8080;
        }
        
        server {
            listen 80;
            server_name _;
            
            location / {
                proxy_pass http://backend;
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
            }
            
            location /health {
                access_log off;
                return 200 "healthy\n";
                add_header Content-Type text/plain;
            }
        }
    }
  mime.types: |
    types {
        text/html                             html htm shtml;
        text/css                              css;
        text/xml                              xml;
        image/gif                             gif;
        image/jpeg                            jpeg jpg;
        image/png                             png;
        application/javascript                js;
        application/json                      json;
    }
```

### Multi-Environment Configuration

```yaml
# Production ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-prod
  namespace: production
data:
  environment: "production"
  log_level: "warn"
  database_url: "postgresql://prod-db:5432/app"
  redis_url: "redis://prod-redis:6379"
  api_rate_limit: "1000"
  enable_debug: "false"
---
# Staging ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-staging
  namespace: staging
data:
  environment: "staging"
  log_level: "debug"
  database_url: "postgresql://staging-db:5432/app"
  redis_url: "redis://staging-redis:6379"
  api_rate_limit: "100"
  enable_debug: "true"
---
# Development ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-dev
  namespace: development
data:
  environment: "development"
  log_level: "debug"
  database_url: "postgresql://dev-db:5432/app"
  redis_url: "redis://dev-redis:6379"
  api_rate_limit: "10"
  enable_debug: "true"
  mock_external_apis: "true"
```

### Service Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: microservice-config
data:
  # Service discovery
  user_service_url: "http://user-service:8080"
  order_service_url: "http://order-service:8080"
  payment_service_url: "http://payment-service:8080"
  
  # Circuit breaker settings
  circuit_breaker_threshold: "5"
  circuit_breaker_timeout: "30s"
  
  # Retry configuration
  max_retries: "3"
  retry_delay: "1s"
  
  # Monitoring
  metrics_enabled: "true"
  tracing_enabled: "true"
  health_check_interval: "30s"
  
  # Complete application config file
  application.yaml: |
    server:
      port: 8080
      shutdown: graceful
    
    spring:
      application:
        name: microservice-app
      datasource:
        url: ${DATABASE_URL}
        username: ${DB_USERNAME}
        password: ${DB_PASSWORD}
      redis:
        host: ${REDIS_HOST}
        port: ${REDIS_PORT}
    
    management:
      endpoints:
        web:
          exposure:
            include: health,info,metrics
      endpoint:
        health:
          show-details: always
    
    logging:
      level:
        com.example: ${LOG_LEVEL:INFO}
      pattern:
        console: "%d{HH:mm:ss.SSS} [%thread] %-5level %logger{36} - %msg%n"
    
    app:
      services:
        user-service: ${USER_SERVICE_URL}
        order-service: ${ORDER_SERVICE_URL}
        payment-service: ${PAYMENT_SERVICE_URL}
      circuit-breaker:
        threshold: ${CIRCUIT_BREAKER_THRESHOLD:5}
        timeout: ${CIRCUIT_BREAKER_TIMEOUT:30s}
```

## Best Practices

### Naming and Organization

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: webapp-config  # Use descriptive, consistent naming
  labels:
    app.kubernetes.io/name: webapp
    app.kubernetes.io/instance: production
    app.kubernetes.io/version: "1.2.3"
    app.kubernetes.io/component: config
    app.kubernetes.io/part-of: ecommerce
    config-type: application
  annotations:
    config.kubernetes.io/description: "Main application configuration"
    config.kubernetes.io/owner: "platform-team"
data:
  # Group related configuration
  # Database settings
  db_host: "postgres.example.com"
  db_port: "5432"
  db_name: "webapp"
  
  # Cache settings  
  cache_host: "redis.example.com"
  cache_port: "6379"
  cache_ttl: "3600"
  
  # Application settings
  app_name: "WebApp"
  app_version: "1.2.3"
  log_level: "info"
```

### Immutable ConfigMaps

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: immutable-config-v1  # Version in name for immutable configs
  labels:
    version: "v1"
    immutable: "true"
data:
  config_version: "1.0.0"
  api_endpoint: "https://api.example.com/v1"
  timeout: "30s"
immutable: true  # Prevents modification
```

### Environment-Specific Configurations

```yaml
# Base configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-base-config
data:
  app_name: "MyApp"
  log_format: "json"
  health_check_path: "/health"
---
# Environment overlay
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-prod-config
data:
  environment: "production"
  log_level: "warn"  
  debug_enabled: "false"
  database_pool_size: "20"
---
# Deployment using both
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      containers:
      - name: app
        image: myapp:latest
        envFrom:
        - configMapRef:
            name: app-base-config
        - configMapRef:
            name: app-prod-config  # Override base with env-specific
```

### Validation and Documentation

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: documented-config
  annotations:
    config.kubernetes.io/schema: |
      {
        "type": "object",
        "properties": {
          "database_url": {"type": "string", "pattern": "^postgresql://"},
          "log_level": {"enum": ["debug", "info", "warn", "error"]},
          "port": {"type": "integer", "minimum": 1024, "maximum": 65535}
        },
        "required": ["database_url", "log_level"]
      }
data:
  # Required fields
  database_url: "postgresql://postgres:5432/mydb"  # Must match pattern
  log_level: "info"  # Must be one of allowed values
  
  # Optional fields with defaults
  port: "8080"  # Must be valid port number
  timeout: "30s"
  
  # Documentation in comments (YAML comments)
  # database_url: PostgreSQL connection string
  # log_level: Logging verbosity (debug|info|warn|error)  
  # port: Application listening port (1024-65535)
  # timeout: Request timeout duration
```

## Troubleshooting

### Common Issues

#### 1. ConfigMap Not Found

```bash
# Check if ConfigMap exists
kubectl get configmap myconfig -o wide

# List all ConfigMaps
kubectl get configmaps

# Check in specific namespace
kubectl get configmap myconfig -n mynamespace

# Verify ConfigMap content
kubectl describe configmap myconfig
kubectl get configmap myconfig -o yaml
```

#### 2. Pod Not Using Updated ConfigMap

```bash
# Check Pod environment variables
kubectl exec mypod -- env | grep -E "(CONFIG|DATABASE)"

# Check mounted files
kubectl exec mypod -- ls -la /etc/config/
kubectl exec mypod -- cat /etc/config/myfile

# Restart Pod to pick up changes (for env vars)
kubectl delete pod mypod
kubectl rollout restart deployment mydeployment

# Check Pod events for mount errors
kubectl describe pod mypod | grep -A 10 Events
```

#### 3. Volume Mount Issues

```bash
# Check if volume is mounted
kubectl exec mypod -- df -h | grep config

# Verify mount path exists
kubectl exec mypod -- ls -la /etc/config/

# Check volume definition in Pod spec
kubectl get pod mypod -o yaml | grep -A 20 volumes

# Verify ConfigMap keys match expected files
kubectl get configmap myconfig -o jsonpath='{.data}' | jq 'keys'
```

### Debugging Commands

```bash
# List all ConfigMaps
kubectl get configmaps
kubectl get cm  # Short form

# Get ConfigMap details
kubectl describe configmap myconfig

# View ConfigMap data
kubectl get configmap myconfig -o yaml
kubectl get configmap myconfig -o json

# Get specific key from ConfigMap
kubectl get configmap myconfig -o jsonpath='{.data.mykey}'

# Create ConfigMap from command line
kubectl create configmap myconfig --from-literal=key1=value1 --from-literal=key2=value2

# Create ConfigMap from file
kubectl create configmap myconfig --from-file=config.yaml

# Create ConfigMap from directory
kubectl create configmap myconfig --from-file=./config-dir/

# Update ConfigMap (if not immutable)
kubectl patch configmap myconfig -p '{"data":{"newkey":"newvalue"}}'

# Export ConfigMap to file
kubectl get configmap myconfig -o yaml > myconfig.yaml

# Test ConfigMap in temporary Pod
kubectl run test-pod --image=busybox --rm -it --restart=Never \
  --env="TEST_VAR" --env-from="configMapRef:name=myconfig" \
  -- env | grep TEST
```

### Configuration Validation

```bash
# Validate YAML syntax
yamllint configmap.yaml

# Validate Kubernetes resource
kubectl apply --dry-run=client -f configmap.yaml

# Check ConfigMap size (max 1MB)
kubectl get configmap myconfig -o json | jq '.data | to_entries | map(.value | length) | add'

# Verify UTF-8 encoding
kubectl get configmap myconfig -o jsonpath='{.data.myfile}' | file -

# Test environment variable expansion
kubectl run env-test --image=alpine --rm -it --restart=Never \
  --env-from="configMapRef:name=myconfig" \
  -- sh -c 'echo "Database: $DATABASE_URL, Log: $LOG_LEVEL"'
```

---

## References

- [Kubernetes Official Documentation: ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Kubernetes API Reference: ConfigMap](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.28/#configmap-v1-core)
- [Configure Pods with ConfigMaps](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/)
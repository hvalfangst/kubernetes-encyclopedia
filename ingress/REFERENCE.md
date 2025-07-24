# Kubernetes Ingress Resource Documentation

## Table of Contents
- [Overview](#overview)
- [API Specification](#api-specification)
- [Field Reference](#field-reference)
- [Ingress Controllers](#ingress-controllers)
- [TLS/SSL Configuration](#tlsssl-configuration)
- [Path Types and Routing](#path-types-and-routing)
- [Common Use Cases](#common-use-cases)
- [Best Practices](#best-practices)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

## Overview

An **Ingress** manages external access to services in a cluster, typically for HTTP traffic, providing load balancing, SSL termination, and name-based virtual hosting.

### Key Features
- HTTP/HTTPS routing to services
- SSL/TLS termination and certificate management
- Name-based virtual hosting
- Path-based routing to different services
- Load balancing across service endpoints
- Integration with cloud provider load balancers

### When to Use Ingress
- **Web applications**: Expose HTTP/HTTPS services externally
- **API gateways**: Route API requests to different services
- **Multi-tenant applications**: Host-based routing
- **SSL termination**: Centralized certificate management
- **Load balancing**: Distribute traffic across services
- **Cost optimization**: Single load balancer for multiple services

## API Specification

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: string
  namespace: string
  labels: {}
  annotations: {}
spec:
  ingressClassName: string            # IngressClass reference
  defaultBackend:                     # Default service for unmatched requests
    service:
      name: string
      port:
        number: integer
        name: string
  tls:                               # TLS configuration
  - hosts: []
    secretName: string
  rules:                             # Routing rules
  - host: string                     # Hostname (optional)
    http:
      paths:
      - path: string                 # URL path
        pathType: string             # Exact, Prefix, ImplementationSpecific
        backend:
          service:
            name: string             # Target service name
            port:
              number: integer        # Service port number
              name: string           # Service port name
status:
  loadBalancer:                      # Load balancer status
    ingress:
    - ip: string
      hostname: string
```

## Field Reference

### Metadata Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Name of the Ingress resource |
| `namespace` | string | Namespace where the Ingress resides |
| `labels` | map[string]string | Key-value pairs for organizing resources |
| `annotations` | map[string]string | Controller-specific configuration |

### Spec Fields

#### ingressClassName
**Type**: `string`  
**Description**: Reference to IngressClass defining which controller handles this Ingress

```yaml
spec:
  ingressClassName: nginx  # Use nginx ingress controller
```

#### defaultBackend
**Type**: `IngressBackend`  
**Description**: Default service for requests that don't match any rules

```yaml
spec:
  defaultBackend:
    service:
      name: default-http-backend
      port:
        number: 80
```

#### tls
**Type**: `[]IngressTLS`  
**Description**: TLS configuration for HTTPS

```yaml
spec:
  tls:
  - hosts:
    - example.com
    - www.example.com
    secretName: example-tls
```

#### rules
**Type**: `[]IngressRule`  
**Description**: List of host and path rules for routing

```yaml
spec:
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /v1
        pathType: Prefix
        backend:
          service:
            name: api-v1-service
            port:
              number: 80
```

## Ingress Controllers

### NGINX Ingress Controller

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - example.com
    secretName: example-tls
  rules:
  - host: example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
```

### AWS Load Balancer Controller

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: aws-ingress
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:region:account:certificate/cert-id
spec:
  rules:
  - host: example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
```

### Google Cloud Load Balancer

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gce-ingress
  annotations:
    kubernetes.io/ingress.class: gce
    kubernetes.io/ingress.global-static-ip-name: web-static-ip
    ingress.gcp.kubernetes.io/managed-certificates: web-ssl-cert
spec:
  rules:
  - host: example.com
    http:
      paths:
      - path: /*
        pathType: ImplementationSpecific
        backend:
          service:
            name: web-service
            port:
              number: 80
```

## TLS/SSL Configuration

### Certificate Management

```yaml
# Using cert-manager for automatic certificates
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: tls-ingress
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - example.com
    - www.example.com
    secretName: example-tls  # Automatically created by cert-manager
  rules:
  - host: example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
```

### Manual Certificate Management

```yaml
# Create TLS secret manually
apiVersion: v1
kind: Secret
metadata:
  name: example-tls
type: kubernetes.io/tls
data:
  tls.crt: LS0tLS1CRUdJTi... # Base64 encoded certificate
  tls.key: LS0tLS1CRUdJTi... # Base64 encoded private key
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: manual-tls-ingress
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - example.com
    secretName: example-tls
  rules:
  - host: example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
```

## Path Types and Routing

### Exact Path Type

```yaml
spec:
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /api/v1/users
        pathType: Exact  # Matches exactly /api/v1/users
        backend:
          service:
            name: user-service
            port:
              number: 80
```

### Prefix Path Type

```yaml
spec:
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /api/v1
        pathType: Prefix  # Matches /api/v1/* 
        backend:
          service:
            name: api-v1-service
            port:
              number: 80
      - path: /api/v2
        pathType: Prefix  # Matches /api/v2/*
        backend:
          service:
            name: api-v2-service
            port:
              number: 80
```

### Implementation Specific

```yaml
spec:
  rules:
  - host: example.com
    http:
      paths:
      - path: /*
        pathType: ImplementationSpecific  # Controller-specific behavior
        backend:
          service:
            name: web-service
            port:
              number: 80
```

## Common Use Cases

### Single Service Exposure

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: simple-ingress
spec:
  ingressClassName: nginx
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp-service
            port:
              number: 80
```

### Multi-Service Routing

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: multi-service-ingress
spec:
  ingressClassName: nginx
  rules:
  - host: example.com
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 80
      - path: /web
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
      - path: /admin
        pathType: Prefix
        backend:
          service:
            name: admin-service
            port:
              number: 80
```

### Name-Based Virtual Hosting

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: virtual-host-ingress
spec:
  ingressClassName: nginx
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 80
  - host: web.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
  - host: admin.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: admin-service
            port:
              number: 80
```

### API Gateway Pattern

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-gateway-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
    nginx.ingress.kubernetes.io/configuration-snippet: |
      more_set_headers "Access-Control-Allow-Origin: *";
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - api.example.com
    secretName: api-tls
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /users(/|$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: user-service
            port:
              number: 80
      - path: /orders(/|$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: order-service
            port:
              number: 80
      - path: /products(/|$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: product-service
            port:
              number: 80
```

## Best Practices

### Security Configuration

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: secure-ingress
  annotations:
    # Force HTTPS
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    
    # Security headers
    nginx.ingress.kubernetes.io/configuration-snippet: |
      more_set_headers "X-Frame-Options: DENY";
      more_set_headers "X-Content-Type-Options: nosniff";
      more_set_headers "X-XSS-Protection: 1; mode=block";
      more_set_headers "Strict-Transport-Security: max-age=31536000; includeSubDomains";
    
    # Rate limiting
    nginx.ingress.kubernetes.io/rate-limit: "100"
    nginx.ingress.kubernetes.io/rate-limit-window: "1m"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - secure.example.com
    secretName: secure-tls
  rules:
  - host: secure.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: secure-service
            port:
              number: 80
```

### Performance Optimization

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: optimized-ingress
  annotations:
    # Enable compression
    nginx.ingress.kubernetes.io/enable-compression: "true"
    
    # Connection pooling
    nginx.ingress.kubernetes.io/upstream-keepalive-connections: "32"
    nginx.ingress.kubernetes.io/upstream-keepalive-requests: "100"
    nginx.ingress.kubernetes.io/upstream-keepalive-timeout: "60"
    
    # Caching
    nginx.ingress.kubernetes.io/server-snippet: |
      location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
      }
spec:
  ingressClassName: nginx
  rules:
  - host: fast.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
```

### Health Checks and Monitoring

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: monitored-ingress
  annotations:
    # Custom health check
    nginx.ingress.kubernetes.io/server-snippet: |
      location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
      }
    
    # Metrics
    nginx.ingress.kubernetes.io/enable-metrics: "true"
spec:
  ingressClassName: nginx
  rules:
  - host: monitored.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
```

## Troubleshooting

### Common Issues

#### 1. Ingress Not Accessible

```bash
# Check if Ingress exists and has correct configuration
kubectl get ingress myingress -o wide

# Verify Ingress controller is running
kubectl get pods -n ingress-nginx

# Check Ingress events
kubectl describe ingress myingress

# Verify DNS resolution
nslookup myapp.example.com

# Check if backend service exists and has endpoints
kubectl get service myservice
kubectl get endpoints myservice
```

#### 2. TLS/SSL Issues

```bash
# Check TLS secret exists and is valid
kubectl get secret mytls-secret -o yaml

# Verify certificate content
kubectl get secret mytls-secret -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout

# Check certificate expiration
kubectl get secret mytls-secret -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -enddate -noout

# Test SSL connection
openssl s_client -connect myapp.example.com:443 -servername myapp.example.com
```

#### 3. Path Routing Issues

```bash
# Test specific paths
curl -H "Host: myapp.example.com" http://ingress-ip/api/v1/test

# Check path configuration
kubectl get ingress myingress -o yaml | grep -A 10 paths

# Verify backend service is accessible
kubectl port-forward service/myservice 8080:80
curl http://localhost:8080/api/v1/test
```

### Debugging Commands

```bash
# List all Ingresses
kubectl get ingress
kubectl get ingress --all-namespaces

# Get Ingress details
kubectl describe ingress myingress

# Check Ingress controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# Test Ingress connectivity
curl -v -H "Host: myapp.example.com" http://ingress-external-ip/

# Check backend service
kubectl get service myservice
kubectl describe service myservice
kubectl get endpoints myservice

# Verify Ingress class
kubectl get ingressclass

# Check controller status
kubectl get pods -n ingress-nginx
kubectl describe pod -n ingress-nginx <controller-pod-name>

# View Ingress in different formats
kubectl get ingress myingress -o yaml
kubectl get ingress myingress -o json

# Test with curl and custom headers
curl -H "Host: api.example.com" -H "X-Forwarded-Proto: https" http://ingress-ip/api/v1
```

### Network Troubleshooting

```bash
# Check if Ingress controller service is accessible
kubectl get service -n ingress-nginx

# Test from within cluster
kubectl run test-pod --image=curlimages/curl --rm -it -- curl -H "Host: myapp.example.com" http://ingress-controller-ip/

# Check firewall rules (cloud provider specific)
# AWS: Security groups
# GCP: Firewall rules
# Azure: Network security groups

# Verify load balancer status
kubectl get service -n ingress-nginx ingress-nginx-controller

# Check external DNS (if using external-dns)
kubectl logs -n external-dns deployment/external-dns
```

---

## References

- [Kubernetes Official Documentation: Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Kubernetes API Reference: Ingress](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.28/#ingress-v1-networking-k8s-io)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
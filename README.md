# Kubernetes Encyclopedia

A comprehensive collection of Kubernetes resources with detailed documentation, example manifests, and deployment scripts for learning and reference.

## 📁 Directory Structure

This repository contains **13 Kubernetes resource types**, each organized in its own directory with complete documentation, manifests, and deployment scripts.

## 🚀 Resources

### Core Workload Resources
| Resource | Description | Directory |
|----------|-------------|-----------|
| **[CronJob](cronjob/REFERENCE.md)** | Schedule-based job execution with cron-like scheduling | `cronjob/` |
| **[Deployment](deployment/REFERENCE.md)** | Stateless application management and rolling updates | `deployment/` |
| **[Job](job/REFERENCE.md)** | Run-to-completion workloads and batch processing | `job/` |
| **[StatefulSet](statefulset/REFERENCE.md)** | Stateful application management with persistent identity | `statefulset/` |
| **[DaemonSet](daemonset/REFERENCE.md)** | Node-level service deployment (one pod per node) | `daemonset/` |

### Networking Resources
| Resource | Description | Directory |
|----------|-------------|-----------|
| **[Service](service/REFERENCE.md)** | Pod networking, service discovery, and load balancing | `service/` |
| **[Ingress](ingress/REFERENCE.md)** | HTTP/HTTPS routing, SSL termination, and external access | `ingress/` |
| **[NetworkPolicy](networkpolicy/REFERENCE.md)** | Network access control and pod-to-pod communication rules | `networkpolicy/` |

### Configuration & Data Resources
| Resource | Description | Directory |
|----------|-------------|-----------|
| **[ConfigMap](configmap/REFERENCE.md)** | Configuration data storage and environment variables | `configmap/` |
| **[Secret](secret/REFERENCE.md)** | Sensitive data management (passwords, tokens, keys) | `secret/` |

### Storage Resources
| Resource | Description | Directory |
|----------|-------------|-----------|
| **[PersistentVolume](persistentvolume/REFERENCE.md)** | Cluster-wide storage resources and volume provisioning | `persistentvolume/` |
| **[PersistentVolumeClaim](persistentvolumeclaim/REFERENCE.md)** | Storage requests and volume binding | `persistentvolumeclaim/` |

### Security & Identity Resources
| Resource | Description | Directory |
|----------|-------------|-----------|
| **[ServiceAccount](serviceaccount/REFERENCE.md)** | Pod identity, authentication, and RBAC integration | `serviceaccount/` |

## 📋 Directory Structure

Each resource directory follows a consistent structure:

```
resource-name/
├── REFERENCE.md    # Comprehensive documentation with examples and best practices
├── manifest.yml    # Ready-to-use example configuration
└── script.sh       # Automated deployment and testing script
```

## 🛠️ Usage

### Quick Start
1. **Navigate** to any resource directory
2. **Review** the `REFERENCE.md` for detailed documentation
3. **Examine** the `manifest.yml` for configuration examples  
4. **Execute** the `script.sh` to deploy and test the resource

### Example Workflow
```bash
# Navigate to a resource directory
cd deployment

# Make script executable (if needed)
chmod +x script.sh

# Deploy the example
./script.sh

# View the reference documentation
cat REFERENCE.md
```

### All Available Resources
```bash
# List all available Kubernetes resource directories
ls -la | grep ^d
```

## 📚 Learning Path

For beginners, we recommend exploring resources in this order:

1. **[ConfigMap](configmap/REFERENCE.md)** - Start with configuration basics
2. **[Secret](secret/REFERENCE.md)** - Learn about sensitive data handling
3. **[Deployment](deployment/REFERENCE.md)** - Core workload management
4. **[Service](service/REFERENCE.md)** - Service discovery and networking
5. **[Ingress](ingress/REFERENCE.md)** - External access and routing
6. **[PersistentVolume](persistentvolume/REFERENCE.md)** & **[PersistentVolumeClaim](persistentvolumeclaim/REFERENCE.md)** - Storage concepts
7. **[StatefulSet](statefulset/REFERENCE.md)** - Stateful applications
8. **[Job](job/REFERENCE.md)** & **[CronJob](cronjob/REFERENCE.md)** - Batch workloads
9. **[DaemonSet](daemonset/REFERENCE.md)** - Node-level services
10. **[ServiceAccount](serviceaccount/REFERENCE.md)** - Identity and security
11. **[NetworkPolicy](networkpolicy/REFERENCE.md)** - Advanced networking and security
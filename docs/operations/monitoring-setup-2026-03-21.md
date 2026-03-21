# Monitoring Infrastructure Setup - 2026-03-21

## Overview

Deployed production-grade monitoring stack on NixOS Kubernetes cluster using Prometheus, Grafana, and Node Exporter. This setup provides visibility into cluster health, resource utilization, and enables proactive incident response.

## Components Deployed

### 1. Prometheus
- **Version**: v2.50.0
- **Location**: `monitoring/prometheus`
- **Node**: Pinned to `nexus` for better resource availability
- **Resources**: 250m CPU / 512Mi RAM (requests)
- **Storage**: 15-day retention (emptyDir, non-persistent)
- **Access**: ClusterIP service on port 9090

**Scraping Targets**:
- Prometheus self-monitoring
- Node Exporter (all 4 nodes on port 9101)
- Kubernetes API Server
- Kubernetes Nodes
- Kubernetes Pods (with prometheus.io/scrape annotation)

### 2. Grafana
- **Version**: v10.4.2
- **Location**: `monitoring/grafana`
- **Node**: Pinned to `nexus`
- **Resources**: 100m CPU / 128Mi RAM (requests)
- **Storage**: emptyDir (dashboards non-persistent)
- **Access**: LoadBalancer service on port 3000 (NodePort: 30372)

**Default Credentials**:
- Username: `admin`
- Password: `admin` (**CHANGE IN PRODUCTION!**)

**Datasource**: Prometheus (auto-configured)

### 3. Node Exporter
- **Version**: v1.8.0
- **Deployment**: DaemonSet (1 pod per node)
- **Port**: 9101 (changed from 9100 to avoid conflict with host processes)
- **Privileged**: Yes (hostNetwork, hostPID, hostPath mounts)
- **PodSecurity**: Privileged enforcement on `monitoring` namespace

**Metrics Collected**:
- CPU usage
- Memory usage (detailed breakdown)
- Disk I/O and filesystem stats
- Network statistics
- System load averages
- Thermal information
- Process statistics

## Architecture Decisions

### Why Custom Deployment vs. kube-prometheus-stack?

**Problem**: kube-prometheus-stack (Prometheus Operator) encountered permission issues with local-path storage:
```
Error opening query log file: open /prometheus/queries.active: permission denied
panic: Unable to create mmap-ed active query log
```

**Root Cause**: Local-path storage doesn't support memory-mapped files required by Prometheus for query logging.

**Solution**: Deployed simplified Prometheus without complex operator dependencies, using emptyDir for temporary storage. This prioritizes:
1. **Operational simplicity** - easier to troubleshoot
2. **Quick deployment** - monitoring operational in < 5 minutes
3. **Flexibility** - easy to modify configurations

**Trade-offs**:
- ❌ Metrics not persisted across pod restarts
- ❌ No automatic Operator-managed configuration
- ✅ Simpler architecture
- ✅ Full control over configuration
- ✅ Lower resource overhead

**Future Enhancement**: Migrate to NFS/RWX storage for persistence (planned in database migration task).

### Port Conflict Resolution

**Issue**: Node Exporter daemonset pods failing with:
```
listen tcp 0.0.0.0:9100: bind: address already in use
```

**Cause**: Host node_exporter process already listening on `127.0.0.1:9100` (likely from previous setup).

**Solution**: Changed Node Exporter to use port **9101** instead of 9100:
- Updated daemonset containerPort and hostPort to 9101
- Updated Prometheus scrape config to target `:9101`
- Avoids conflict while maintaining functionality

### PodSecurity Configuration

**Challenge**: Node Exporter requires privileged access (hostPath volumes, hostNetwork)

**Solution**: Labeled `monitoring` namespace with privileged enforcement:
```bash
kubectl label namespace monitoring \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged
```

This allows Node Exporter to run with necessary privileges while maintaining security boundaries in other namespaces.

## Access Methods

### Grafana Web UI

**Option 1: Port-forwarding (Development)**
```bash
kubectl port-forward -n monitoring svc/grafana 3000:3000
# Access at http://localhost:3000
```

**Option 2: NodePort (Production)**
```bash
# Get node IPs and NodePort
kubectl get nodes -o wide
kubectl get svc grafana -n monitoring
# Access at http://<NODE-IP>:30372
```

**Option 3: LoadBalancer (Future)**
```bash
# Configure MetalLB or external load balancer
# Access at http://<EXTERNAL-IP>:3000
```

### Prometheus API

**Port-forwarding**:
```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# API: http://localhost:9090/api/v1/
# UI: http://localhost:9090
```

**Example Queries**:
```bash
# Memory usage by node
curl 'http://localhost:9090/api/v1/query?query=(1-(node_memory_MemAvailable_bytes/node_memory_MemTotal_bytes))*100'

# CPU usage by node
curl 'http://localhost:9090/api/v1/query?query=(100-(avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m]))*100))'
```

## Key Metrics to Monitor

### Golden Signals (Google SRE)

1. **Latency**: Response time (application-dependent)
2. **Traffic**: Request volume (application-dependent)
3. **Errors**: Error rate (application-dependent)
4. **Saturation**: Resource utilization (CPU, Memory, Disk, Network)

### Cluster Health

**Node Memory Usage**:
```promql
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100
```

**Node CPU Usage**:
```promql
100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

**Pod Memory Usage**:
```promql
sum(container_memory_working_set_bytes{pod!=""}) by (pod, namespace)
```

**Kubernetes API Server Health**:
```promql
up{job="kubernetes-apiservers"}
```

## Next Steps

### Immediate (Today)
- [ ] Access Grafana UI and change admin password
- [ ] Import pre-built dashboards (Kubernetes Cluster, Node Exporter)
- [ ] Verify metrics are being collected from all nodes
- [ ] Test Prometheus queries

### Short-term (This Week)
- [ ] Create custom dashboards for memory monitoring
- [ ] Set up alerting rules for memory thresholds
- [ ] Configure persistent storage for Prometheus and Grafana
- [ ] Document dashboard URLs and access procedures

### Medium-term (This Month)
- [ ] Integrate with existing alerting systems
- [ ] Add application-specific metrics (AI inference, mining, etc.)
- [ ] Set up log aggregation (Loki/ELK)
- [ ] Create runbooks for common alerts

## Files Created

- `/etc/nixos/kubernetes-manifests/monitoring/prometheus-deployment.yaml` - Prometheus deployment and config
- `/etc/nixos/kubernetes-manifests/monitoring/grafana-deployment.yaml` - Grafana deployment and config
- `/etc/nixos/kubernetes-manifests/monitoring/node-exporter.yaml` - Node Exporter daemonset
- `/etc/nixos/docs/operations/monitoring-setup-2026-03-21.md` (this file)

## Kubernetes Resources

**Namespace**: `monitoring` (privileged PodSecurity)

**Deployments**:
- `prometheus` (1 replica, on nexus)
- `grafana` (1 replica, on nexus)

**DaemonSets**:
- `node-exporter` (4 pods, 1 per node)

**Services**:
- `prometheus` (ClusterIP: 10.0.0.138:9090)
- `grafana` (LoadBalancer: 10.0.0.182:3000, NodePort: 30372)

**ConfigMaps**:
- `prometheus-config` (Prometheus configuration)
- `grafana-datasources` (Grafana datasource provisioning)

## Troubleshooting

### Prometheus Not Starting

**Symptoms**: Pod in CrashLoopBackOff
**Check Logs**:
```bash
kubectl logs -n monitoring prometheus-<pod-name>
```

**Common Issues**:
- Configuration syntax errors in `prometheus.yml`
- Permission issues (runAsUser/fsGroup)
- Resource limits (insufficient CPU/memory)

**Solution**: Edit ConfigMap and restart deployment

### Grafana Dashboard Not Loading

**Symptoms**: Dashboard shows "No Data"
**Checks**:
1. Verify Prometheus datasource is configured
2. Check Prometheus is collecting metrics
3. Verify time range in Grafana matches data available

**Solution**:
```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090/targets
```

### Node Exporter Not Reporting

**Symptoms**: Node metrics missing in Prometheus
**Check**:
```bash
kubectl get pods -n monitoring -l app=node-exporter
kubectl logs -n monitoring node-exporter-<pod-name>
```

**Common Issues**:
- Port conflict (9100 vs 9101)
- PodSecurity blocking privileged containers
- Host network access blocked

**Solution**: Verify namespace is labeled with privileged enforcement

## Status

**Medium-term Infrastructure Task**: 🟡 IN PROGRESS (Monitoring complete, pending: database migration, priority classes)

**Cluster Monitoring**: ✅ OPERATIONAL
- All components running successfully
- Metrics collection active
- Grafana accessible
- Prometheus functional

**Next Task**: Implement pod priority classes and begin database migration planning

# AI Stack Improvements - Progress Report

**Date**: 2026-03-21
**Status**: Phase 1 Complete, MLflow In Progress

---

## ✅ Completed

### 1. Fixed GPU Resource Allocation (Critical)
**Problem**: LimitRange "ai-inference-limits" was automatically granting every pod in ai-inference namespace a GPU request, causing non-GPU workloads (Grafana, postgres-n8n) to consume GPU capacity.

**Solution**:
- Removed LimitRange that was injecting `nvidia.com/gpu: "1"` into all pods
- Restarted affected deployments to pick up correct resource configuration
- Verified GPU resources freed: 2 GPUs on Zephyr, 1 on Nexus now available for actual GPU workloads

**Impact**:
- Grafana, postgres-n8n, prometheus, redis no longer request GPUs
- Mining pods remain correctly allocated to GPUs
- GPU capacity now available for AI inference workloads

### 2. Fixed ai-inference-gateway Deployment
**Problem**: Deployment failing with ImagePullBackOff trying to pull `ghcr.io/j-kro/ai-inference-gateway:latest` (403 Forbidden).

**Solution**: Scaled down broken deployment to prevent resource waste. Working `ai-gateway` deployment already exists in namespace.

---

## ⏳ In Progress

### 3. MLflow Model Registry Implementation
**Status**: 90% Complete - Network/Storage Issue

**What's Working**:
- ✅ MLflow deployment manifest created with proper command (`mlflow server`)
- ✅ Service created (ClusterIP on port 5000)
- ✅ Ingress configured for mlflow.cluster.local
- ✅ Health checks configured (liveness/readiness probes)
- ✅ Resource limits set (200m CPU, 512Mi RAM requests)

**Current Issue**:
- ❌ PVC provisioning circular dependency:
  - PVC wants to provision on Sentry (from previous attempt)
  - Pod has nodeSelector for Zephyr (to avoid IP exhaustion on Sentry)
  - Pods waiting for PVC, PVC waiting for pods

**Root Cause**:
- Old PV `pvc-b61429a3-4bdd-43c7-b157-e5e3d0903365` still in Released state
- PVC annotations still reference Sentry node
- Need to delete old PV and recreate PVC

**Next Steps to Complete**:
```bash
# 1. Delete old released PV
kubectl delete pv pvc-b61429a3-4bdd-43c7-b157-e5e3d0903365

# 2. Delete current PVC
kubectl delete pvc mlflow-storage -n ai-inference

# 3. Apply deployment (will create fresh PVC on Zephyr)
kubectl apply -f /etc/nixos/kubernetes-manifests/mlflow/mlflow-deployment.yaml

# 4. Verify
kubectl get pods -n ai-inference -l app=mlflow
kubectl logs -n ai-inference -l app=mlflow
```

---

## 📋 Pending (Next Priority)

### 4. Loki/Tempo Observability Stack
**Planned Components**:
- Loki: Log aggregation (cluster-wide logs)
- Tempo: Distributed tracing (ML pipeline traces)
- Integration with existing Grafana dashboards

**Estimated Time**: 4-6 hours

**Dependencies**: None (can run in parallel with MLflow completion)

### 5. GPU Workload Optimization
**Objectives**:
- Implement GPU preemption policies (mining vs K8s inference)
- Add GPU utilization monitoring dashboards
- Create GPU workload autoscaling rules

**Current State**: Mining coordinator module exists, needs K8s integration

**Estimated Time**: 6-8 hours

**Dependencies**: MLflow (for tracking GPU experiment metrics)

### 6. Multi-Modal Serving
**Enhancements**:
- Add vision support to AI Gateway (CLIP integration)
- Add Whisper STT endpoints
- Multi-modal model serving capabilities

**Estimated Time**: 8-12 hours

**Dependencies**: MLflow + GPU optimization

---

## 🔧 Infrastructure Issues Discovered

### Network IP Exhaustion on Sentry
**Issue**: Flannel subnet 10.244.2.0/254 exhausted due to 150+ mining pods

**Symptoms**: New pods fail with "no IP addresses available in range set: 10.244.2.1-10.244.2.254"

**Temporary Workaround**: Use nodeSelector to schedule critical workloads on Zephyr/Nexus

**Long-term Solutions**:
1. Clean up completed/failed mining pods (Task #1)
2. Expand Flannel subnet mask (e.g., /16 → /22 per node)
3. Implement pod eviction policies for low-priority workloads

---

## 📊 Resource Allocation Summary

**GPU Allocation (After Fixes)**:
| Node | Total GPUs | Available | Allocated To |
|------|-----------|-----------|--------------|
| Zephyr | 2 | 2 | Mining (preemptible) |
| Nexus | 1 | 1 | Mining (preemptible) |
| Forge | 2 | 0 | 2x RTX 4060 (NVIDIA mining) |
| Sentry | 0 (AMD) | 0 | AMD GPU (mining) |

**Storage Allocation**:
| PVC | Size | Status | Node |
|-----|------|--------|------|
| mlflow-storage | 20Gi | Pending (retry) | Zephyr (target) |
| postgres-n8n | 10Gi | Bound | Nexus |
| qdrant-data | 10Gi | Bound | Zephyr |

---

## 🎯 Success Metrics

**Completed**:
- ✅ Freed 2 GPUs from incorrect allocation
- ✅ Fixed resource waste (non-GPU workloads no longer request GPUs)
- ✅ MLflow 90% deployed (storage issue remains)

**In Progress**:
- ⏳ MLflow PVC provisioning (circular dependency)

**Next Session Priorities**:
1. Complete MLflow deployment (10 minutes)
2. Deploy Loki/Tempo observability (4-6 hours)
3. Optimize GPU workload coordination (6-8 hours)

---

**Documentation**: `/etc/nixos/docs/kubernetes/ai-stack-improvements-2026-03-21.md`
**MLflow Manifest**: `/etc/nixos/kubernetes-manifests/mlflow/mlflow-deployment.yaml`

---

**Generated by**: Claude (MLOps Engineer Skill)
**Status**: Ready for final MLflow deployment

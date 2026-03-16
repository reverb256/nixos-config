---
name: k8s-migration
description: Guide the Kubernetes migration following the 9-week roadmap
version: 1.0.0
author: j_kro
license: MIT
metadata:
  hermes:
    tags: [Kubernetes, K8s, Migration, Roadmap]
---

# Kubernetes Migration Guide

Follow the 9-week migration plan from ROADMAP.md.

## Current Status

Phase 1 Complete: K8s v1.35.0 running on Zephyr

## Migration Phases

### Phase 2: Core Services (Weeks 2-4)
- Storage: Longhorn distributed storage
- Ingress: NGINX or Traefik
- Cert-Manager: TLS automation
- Monitoring: Prometheus + Grafana

### Phase 3: Application Migration (Weeks 5-7)
- AI Inference Gateway → StatefulSet
- Qdrant → Helm Chart
- Services → Deployments

### Phase 4: Optimization (Weeks 8-9)
- HPA: Horizontal Pod Autoscaling
- VPA: Vertical Pod Autoscaling
- GitOps: ArgoCD integration

## Validation Checklist

After each phase:
- [ ] Pods are running
- [ ] Services are accessible
- [ ] Data persistence works
- [ ] Backups are functional

## Rollback Plan

If migration fails:
```bash
# Revert to NixOS configs
just deploy

# Disable affected services
kubectl delete -f <manifest>
```

## References
- Full roadmap: ROADMAP.md
- K8s docs: docs/kubernetes/

# K8s Infrastructure Refactoring Runbook
## Completed: 2026-05-03

## What Was Done

### Monitoring Stack Migration: sentry -> nexus
All 4 monitoring workloads migrated from sentry to nexus:
- grafana (Deployment, 10Gi) - data restored via kubectl cp
- loki (StatefulSet, 50Gi) - data restored via direct host rsync  
- mimir (StatefulSet, 100Gi) - corrupt TSDB cleaned, fresh start
- tempo (StatefulSet, 50Gi) - fresh volume (data was 4K)

### StatefulSet Recreation Pattern
StatefulSets were deleted with --cascade=orphan and recreated because
volumeClaimTemplates cannot be patched on existing StatefulSets.

### Storage Class Fix
slow-hdd had allowedTopologies restricted to sentry only.
Patched to allow all nodes. New PVCs use local-path (no topology restriction).

### Node Topology Labels
- zephyr: default-zone
- nexus: default-zone
- forge: gpu-zone
- sentry: monitoring-zone

### Network Policies
Applied default-deny + allow policies to ai-inference and monitoring.
75 total NetworkPolicies across all namespaces.

## Current State
- All monitoring pods: Running on nexus
- All PVCs: local-path storage class, Bound on nexus
- Grafana: healthy (db ok, v12.4.3)
- Sentry: freed from monitoring workloads

## Files Created
| File | Purpose |
|------|---------|
| /etc/nixos/cluster/topology.nix | Single source of truth |
| /etc/nixos/modules/system/network.nix | Auto /etc/hosts + firewall |
| /etc/nixos/modules/system/ssh-autodiscover.nix | SSH config from topology |
| /etc/nixos/kubernetes-manifests/storage-classes/ | sc-fast, topo-aware |
| /etc/nixos/kubernetes-manifests/network-policies/ | Label-based policies |
| /home/j_kro/bin/pvc-migrate.sh | PVC migration helper |
| /etc/nixos/docs/runbook.md | This runbook |

## Rollback
```bash
# Revert monitoring to sentry (old backups in ~/tmp/)
kubectl apply -f ~/tmp/loki-backup.yaml
kubectl apply -f ~/tmp/mimir-backup.yaml
# Full config rollback
cd /etc/nixos && sudo git revert HEAD && just deploy
```

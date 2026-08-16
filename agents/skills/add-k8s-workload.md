# Adding a Kubernetes workload

**Last verified:** 2026-08-16

## Scheduling (Zephyr OOM prevention)

Zephyr has constant RAM pressure (31GB). Default **all** non-infrastructure,
non-mining workloads to Nexus (46GB).

| Node | RAM | Use for |
|------|-----|---------|
| Nexus | 46GB | Default for all workloads |
| Zephyr | 31GB | Infrastructure + mining only |
| Forge | 15GB | Mining + GPU compute |
| Sentry | 31GB | Monitoring + Vulkan AI inference |

Priority: **Nexus > Forge > Sentry > Zephyr**. Enforce with
`spec.template.spec.nodeName: nexus` (preferred) or `nodeAffinity`.

Before any nodeSelector change, check capacity:

```bash
kubectl top nodes
kubectl describe node <n> | grep -A 5 "Allocated resources"
kubectl get replicasets -A --no-headers | wc -l
```

## Deployment hygiene (mandatory)

- Explicit `replicas: 1`; `revisionHistoryLimit: 2`; `maxSurge: 0` in RollingUpdate.
- `Recreate` for GPU workloads, `RollingUpdate` for stateless.
- Scale to 0 before deleting; never `kubectl delete --all` / `scale --all`.
- `default-scheduler` only — never `volcano-scheduler` for stateless workloads.
- `app.kubernetes.io/managed-by: easykubenix` label; `_namedlist = true` on
  easykubenix containers/volumes/volumeMounts/env blocks.
- Pin all images; `:latest` is blocked by `kubernetes-manifests/security/deny-latest-tag.yaml`.

## GPU isolation caveat

`nvidia-container-runtime` is broken on NixOS (libnvidia-ml.so.1 dlopen fails).
`CUDA_VISIBLE_DEVICES` is a hint that llama.cpp/vLLM respect but does not
enforce. Use `mining-inference-coordinator` to shift mining while inference runs.

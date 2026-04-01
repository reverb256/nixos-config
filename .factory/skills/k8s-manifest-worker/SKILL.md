---
name: k8s-manifest-worker
description: Worker for Kubernetes manifest changes (deployments, services, network policies, HPA, RBAC, cleanup)
---

# K8s Manifest Worker

NOTE: Startup and cleanup are handled by `mission-worker-base`. This skill defines the WORK PROCEDURE.

## When to Use This Skill

Features that involve creating, modifying, or deleting Kubernetes manifest files (YAML) and applying them to the cluster. Also covers RBAC fixes, network policy changes, HPA creation, and cleanup of stale resources.

## Required Skills

None (all tools are standard bash/kubectl)

## Work Procedure

1. **Read the feature description carefully** - understand exactly what K8s resources need changing
2. **Investigate current state BEFORE making changes**:
   ```bash
   # Check current deployment/pod/service status
   kubectl get deploy,pods,svc,hpa,limitrange,networkpolicy -n ai-inference
   kubectl get pods -n ingress-system -o wide
   kubectl get events -n ai-inference --sort-by='.lastTimestamp' | tail -20
   ```
3. **Read existing manifest files** - understand the current structure before editing
4. **Make changes following cluster conventions**:
   - Use DNS names (not hardcoded IPs) in all manifests
   - Set `maxSurge: 0` and `revisionHistoryLimit: 2` on all deployments
   - Use `nodeSelector` for node pinning (not `nodeName` where possible)
   - Use `default-scheduler` (NOT yunikorn/volcano)
   - For GPU workloads: MUST include `runtimeClassName: nvidia` in pod spec
   - For GPU workloads: MUST include `--device=cuda` in container args for vLLM
   - Set resource requests AND limits on all containers
   - Use `imagePullPolicy: IfNotPresent` or `Never` for local images
5. **Apply changes**:
   ```bash
   kubectl apply -f <manifest-file>
   ```
6. **Verify the change worked**:
   ```bash
   # Wait for rollout
   kubectl rollout status deploy/<name> -n ai-inference --timeout=300s
   # Check pod status
   kubectl get pods -n ai-inference -o wide
   # Check logs for errors
   kubectl logs -n ai-inference -l app=<label> --tail=50
   ```
7. **Run health checks** as specified in the feature's verificationSteps
8. **Commit**: Stage only changed files, commit with descriptive message

### Critical Safety Rules

- **NEVER** schedule workloads to Zephyr (RAM constrained - infrastructure only)
- **NEVER** use `--all` flags with kubectl delete/scale
- **NEVER** scale deployments without checking current state first
- **ALWAYS** check `kubectl top nodes` before adding workloads
- **ALWAYS** verify the change didn't break existing services
- For Forge GPU workloads: miners must be scaled to 0 BEFORE deploying (requires user approval)
- The vLLM image has its own Python/CUDA - do NOT mount NixOS bin/lib paths
- The `runtimeClassName: nvidia` is REQUIRED for GPU passthrough

### Key Cluster Facts

- Caddy namespace: `ingress-system` (NOT `caddy-ingress`)
- Caddy is a DaemonSet with label `app=caddy-ingress`
- Forge miners: TWO deployments `gpu-miner-forge-nvidia-0` and `gpu-miner-forge-nvidia-1`
- LimitRange name: `default-limits` in ai-inference namespace
- AI inference gateway uses `hostNetwork: true` on Zephyr, port 8081
- Priority class `ai-inference-high` (value 900) already exists in cluster

## Example Handoff

```json
{
  "salientSummary": "Fixed vLLM deployment by adding runtimeClassName: nvidia and --device=cuda flag. Reduced memory limit to 4Gi to comply with LimitRange. Applied updated manifest and verified pod reaches Running state with CUDA GPU initialization in logs.",
  "whatWasImplemented": "Added runtimeClassName: nvidia to vLLM pod spec. Added --device=cuda to container args. Set memory limit to 4Gi. Removed command override (image has correct entrypoint). Set maxSurge: 0, revisionHistoryLimit: 2. Verified pod starts on Nexus with GPU allocation.",
  "whatWasLeftUndone": "",
  "verification": {
    "commandsRun": [
      { "command": "kubectl apply -f kubernetes-manifests/ai-inference/vllm/vllm-deployment.yaml", "exitCode": 0, "observation": "Deployment updated" },
      { "command": "kubectl get pods -n ai-inference -l app=vllm-qwen -o wide", "exitCode": 0, "observation": "Pod Running on nexus" },
      { "command": "kubectl logs -n ai-inference -l app=vllm-qwen --tail=20 | grep -i cuda", "exitCode": 0, "observation": "CUDA GPU detected, model loading" },
      { "command": "kubectl exec -n ai-inference deploy/ai-inference-gateway -- curl -s http://vllm-qwen.ai-inference.svc.cluster.local:8000/health", "exitCode": 0, "observation": "HTTP 200" }
    ],
    "interactiveChecks": []
  },
  "tests": { "added": [] },
  "discoveredIssues": []
}
```

## When to Return to Orchestrator

- `kubectl apply` fails and the fix requires changes outside the feature scope
- Feature requires a NixOS config change (escalate to nixos-config-worker)
- A manifest references a resource/service that doesn't exist and needs to be created first
- GPU passthrough doesn't work despite runtimeClassName: nvidia (may be NixOS config issue)
- Network policy fix requires changes in multiple namespaces not covered by the feature

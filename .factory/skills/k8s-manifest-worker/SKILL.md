---
name: k8s-manifest-worker
description: Worker for Kubernetes manifest cleanup (dead file deletion, consolidation, restructuring, secret migration)
---

# K8s Manifest Worker

NOTE: Startup and cleanup are handled by `mission-worker-base`. This skill defines the WORK PROCEDURE.

## When to Use This Skill

Features that involve cleaning up Kubernetes manifest files: deleting dead/superseded manifests, consolidating scattered resources, restructuring directories, and migrating plaintext secrets to agenix.

## Required Skills

None (all tools are standard bash/file editing)

## Work Procedure

1. **Read the feature description carefully** - understand exactly which files to delete, move, or modify
2. **BEFORE any deletion, verify the resource is not active**:
   ```bash
   # Check if a deployment/resource exists in the cluster
   kubectl get <resource-type> <name> -n <namespace> 2>&1
   
   # Check if any pod is running with the resource
   kubectl get pods -A | grep <keyword>
   ```
3. **For file deletions**: Use `git rm` to remove files (preserves history)
4. **For directory consolidation**:
   - Create target directory if needed
   - `git mv` files to new location
   - Verify no other manifests reference the old path (K8s manifests don't import each other, but scripts might)
5. **For secret migration**:
   - Extract the secret value from the manifest
   - Create an agenix secret file in `/etc/nixos/secrets/`
   - Update the K8s manifest to reference a proper K8s Secret (not inline)
   - Ensure the NixOS config includes the agenix secret
6. **After all changes, verify cluster state**:
   ```bash
   # No resources should be missing compared to before
   kubectl get deployments -A
   kubectl get daemonsets -A
   kubectl get services -A
   kubectl get configmaps -A
   ```
7. **Commit**: Stage only changed files, commit with descriptive message

### Safety Rules

- **NEVER** delete a manifest for an actively deployed resource without confirming it's safe
- **NEVER** delete files in `kubernetes-manifests/` that are referenced by running deployments
- **ALWAYS** run `kubectl get` before deleting to confirm resource status
- **ALWAYS** use `git rm` (not `rm`) so history is preserved
- If uncertain whether a manifest is active, VERIFY first — do not guess
- For scripts (`.sh` files), check if they're referenced anywhere: `rg -l <script-name> /etc/nixos/`

### Verification Pattern

Before deleting a file, verify it's safe:
```bash
# 1. Is the K8s resource active?
kubectl get <kind> <name> -n <namespace>

# 2. Is the file referenced elsewhere?
rg -l '<filename>' /etc/nixos/kubernetes-manifests/

# 3. Is it referenced in any NixOS config?
rg -l '<filename>' /etc/nixos/modules/ /etc/nixos/hosts/

# 4. Is it referenced in any docs?
rg -l '<filename>' /etc/nixos/docs/
```

## Example Handoff

```json
{
  "salientSummary": "Deleted 28 dead K8s manifest files: Istio manifests (2), MLflow (1), Volcano scheduler (3), YuniKorn (4), GitOps skeleton (3 dirs), test pods (8), superseded deployment variants (7). Verified no active K8s resources were affected. All deletions are git-tracked for recovery.",
  "whatWasImplemented": "Removed istio-zephyr.yaml, ai-inference/istio-mesh.yaml, mlflow/, scheduling/volcano/, scheduling/yunikorn/, gitops/ directory, mining/test*.yaml (4 files), mining/debug-container.yaml, test/ directory (2 files), gpu/gpu-*-test.yaml (4 files), superseded cloudflared variants (cloudflared.yaml, cloudflared-working.yaml, cloudflared-config.yaml), AI gateway variants (gateway-deployment-simple, -yunikorn, -yunikorn-fixed, -refactored, -diagnostic), n8n/deployment.yaml, home-assistant/deployment.yaml.",
  "whatWasLeftUndone": "",
  "verification": {
    "commandsRun": [
      { "command": "kubectl get deployments -A --no-headers | wc -l", "exitCode": 0, "observation": "Same count as before (15 deployments)" },
      { "command": "kubectl get pods -A --no-headers | grep -v Running | grep -v Completed", "exitCode": 0, "observation": "No unexpected pod states" },
      { "command": "rg -l 'istio' /etc/nixos/kubernetes-manifests/", "exitCode": 1, "observation": "No remaining istio references" },
      { "command": "rg -l 'volcano' /etc/nixos/kubernetes-manifests/", "exitCode": 1, "observation": "No remaining volcano references" }
    ],
    "interactiveChecks": []
  },
  "tests": { "added": [] },
  "discoveredIssues": []
}
```

## When to Return to Orchestrator

- A manifest marked for deletion corresponds to an actively deployed resource
- A manifest is referenced by another manifest or NixOS config that wasn't in the feature scope
- Secret migration requires decisions about K8s Secret vs agenix approach
- Directory restructuring would break K8s apply paths referenced in NixOS config

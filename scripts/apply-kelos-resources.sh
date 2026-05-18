#!/usr/bin/env bash
set -euo pipefail
NAMESPACE="kelos-system"

apply_ws() { local N=$1 R=$2
  kubectl apply -n "$NAMESPACE" -f - <<YAML
apiVersion: kelos.dev/v1alpha1
kind: Workspace
metadata:
  name: $N
  labels:
    app.kubernetes.io/managed-by: easykubenix
    app.kubernetes.io/part-of: kelos
spec:
  repo: https://github.com/reverb256/$R.git
  ref: main
  secretRef:
    name: github-token
  setupCommand:
  - sh
  - -c
  - chmod -R g+rw /workspace/repo
YAML
  echo "  WS $N"
}

apply_sp() { local S=$1 R=$2 W=$3
  kubectl apply -n "$NAMESPACE" -f - <<YAML
apiVersion: kelos.dev/v1alpha1
kind: TaskSpawner
metadata:
  name: github-issues-$S
  labels:
    app.kubernetes.io/managed-by: easykubenix
    app.kubernetes.io/part-of: kelos
spec:
  when:
    githubIssues:
      repo: reverb256/$R
      labels: [agent-ready]
      state: open
      pollInterval: 5m
  taskTemplate:
    type: opencode
    credentials:
      type: api-key
      secretRef:
        name: opencode-credentials
    workspaceRef:
      name: $W
    agentConfigRef:
      name: cluster-coder
    branch: kelos-task-{{.Number}}
    promptTemplate: |
      GitHub issue #{{.Number}}: {{.Title}}

      Description:
      {{.Body}}

      Implement, push branch, open PR against main.
      Branch: kelos-task-{{.Number}}
      Workspace at /workspace/repo is writable.
    ttlSecondsAfterFinished: 3600
    podOverrides:
      podSecurityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      resources:
        requests:
          cpu: 250m
          memory: 512Mi
        limits:
          cpu: "1"
          memory: 1Gi
      containerSecurityContext:
        runAsNonRoot: true
        allowPrivilegeEscalation: false
        capabilities:
          drop: [ALL]
        seccompProfile:
          type: RuntimeDefault
  maxConcurrency: 2
YAML
  echo "  SP $S"
}

REPOS=(
  "nixos-config:nixos-config"
  "ai-inference-gateway:ai-inference-gateway"
  "maplespike:maplespike"
  "knowledge-fabric:knowledge-fabric"
  "compute-market:compute-market"
  "mcp-registry:mcp-registry"
  "gpu-proxy:gpu-proxy"
  "llama-cpp-turboquant:llama-cpp-turboquant"
  "vllm-turboquant:vllm-turboquant"
  "searxng-cluster:searxng-cluster"
  "caddy-ingress:caddy-ingress"
  "vane:Vane"
)

echo "=== Kelos Resources ==="
for entry in "${REPOS[@]}"; do
  name="${entry%%:*}"
  repo="${entry##*:}"
  apply_ws "$name" "$repo"
done
for entry in "${REPOS[@]}"; do
  name="${entry%%:*}"
  repo="${entry##*:}"
  apply_sp "$name" "$repo" "$name"
done
echo "=== Done ==="

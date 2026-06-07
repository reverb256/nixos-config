# K8s & AI Infrastructure Remediation Plan

**Created:** 2026-05-11
**Source Audit:** K8s + AI infra audit by Sisyphus (2026-05-11)
**Status:** Plan — awaiting decisions before execution
**Last Verified:** 2026-05-11

---

## Overview

This plan addresses 20 findings from the comprehensive K8s and AI infrastructure audit.
Findings are organized into four phases by severity: **Critical → High → Medium → Low**.

---

## Phase 0: Quick Wins (5-15 min each, no cluster risk)

### 0.1 — Remove hardcoded Grafana admin password

**Files:**
- `kubernetes/modules/mcp-servers.nix` (line 78)

**Problem:**
```nix
GRAFANA_PASSWORD.value = "admin";  # Plaintext in git
```

**Fix:**
Replace with secretKeyRef from `grafana-admin-secret` (already exists in monitoring namespace):

```nix
GRAFANA_PASSWORD.valueFrom.secretKeyRef = {
  name = "grafana-admin-secret";
  key = "admin-password";
};
```

**Risk:** None — Grafana MCP server is in `mcp` namespace, the secret is in `monitoring`. May need a cross-namespace secret reference or a new secret in the `mcp` namespace populated by `kubectl-apply-k8s-secrets`.

**Status:** [ ] Pending

---

### 0.2 — Remove hardcoded n8n Postgres password

**Files:**
- `kubernetes/modules/automation.nix` (line 44)

**Problem:**
```nix
postgres-password = "n8n";  # Literal password in Nix
```

**Fix:**
Replace with empty placeholder and add to `k8s-secret-bootstrap` on zephyr (see `hosts/zephyr/services.nix` line 34-48 for the existing pattern):

```nix
# automation.nix — placeholder
Secret.n8n-secrets.stringData."postgres-password" = "";
```

Then add to zephyr's secret bootstrap list.

**Risk:** None — n8n will need to be restarted after secret population.

**Status:** [ ] Pending

---

### 0.3 — Pin kubernetes-mcp-server image tag

**Files:**
- `kubernetes/modules/infrastructure.nix` (line 144)

**Problem:**
```nix
image = "ghcr.io/containers/kubernetes-mcp-server:latest-linux-amd64";
```

**Fix:**
Pin to current digest or a specific semver tag. Check current version running in cluster first.

```nix
image = "ghcr.io/containers/kubernetes-mcp-server:v0.1.0-linux-amd64";
# OR
image = "ghcr.io/containers/kubernetes-mcp-server@sha256:...";
```

**Risk:** Low — pinning prevents surprise upgrades. Need to determine the current running version.

**Status:** [ ] Pending

---

## Phase 1: Critical Fixes (deploy-blocking)

### 1.1 — Fix Sentry port mismatch

**Files:**
- `kubernetes/modules/ai-inference.nix` — ConfigMap `ai-gateway-config` → `BACKEND_URL`
- `kubernetes/modules/llama-servers.nix` — Deployment `llama-server-sentry` containerPort

**Problem:**
The AI gateway ConfigMap sets `BACKEND_URL = "http://10.1.1.140:1235"` but the `llama-server-sentry` deployment exposes containerPort **1237** (all probes use 1237, service maps to 1237). If sentry ever scales up, the gateway can't reach it.

**Options:**
- **A (Recommended):** Align the gateway to port 1237
  - Change `BACKEND_URL` in `ai-inference.nix` ConfigMap to `http://10.1.1.140:1237`
  - Change `BACKEND_FALLBACK_URLS` similarly if set
- **B:** Change the sentry deployment to listen on 1235

**Recommendation:** Option A — the sentry deployment exposes 1237 consistently (all probes, service, other configs reference 1237).

```nix
# ai-inference.nix ConfigMap change
BACKEND_URL = "http://${cluster.hosts.sentry.ip}:1237";
```

**Risk:** None if sentry is currently `replicas=0`. When scaled to 1, it will be reachable.

**Status:** [ ] Pending

---

### 1.2 — Map ai-inference + llama-servers to host manifests

**Files:**
- `flake.nix` — `hosts` definition, `kubernetes` output
- `kubernetes/default.nix` — manifest definitions

**Problem:**
`ai-inference` and `llama-servers` manifest groups exist in `kubernetes/default.nix` but **no host references them** in `flake.nix`. They're only in the legacy `combined` manifest. Currently it's unclear how they get deployed.

**Diagnostic needed first:**
```bash
# Check if these namespaces exist in the running cluster
kubectl get ns ai-inference
kubectl get deployments -n ai-inference
# Check which manifest is being used  
ssh zephyr "systemctl cat k8s-nix-deploy | grep manifestPackage"
```

**Options:**
- **A (Recommended):** If `combined` manifest is deployed on one host, split cleanly: add `ai-inference` and `llama-servers` to the `small` manifest group or create explicit mappings.
- **B:** Document the current deployment method if it's manual.

**Implementation (if Option A):**
```nix
# kubernetes/default.nix — add to small manifest
small = mkManifest "small" [
  ./modules/ai-inference.nix    # ADD
  ./modules/llama-servers.nix   # ADD
  # ... existing modules ...
];
```

Or deploy as standalone on nexus:
```nix
# flake.nix — add host manifest mapping
nexus = {
  hostName = "nexus";
  k8sManifest = self.kubernetes.small;  # small + ai-inference + llama-servers
};
```

**Risk:** Need to verify current deployment method before changes. Could cause duplicate resource errors if `combined` is already deploying these.

**Status:** [ ] Pending — REQUIRES CLUSTER DIAGNOSTIC FIRST

---

### 1.3 — Create ingress-system namespace

**Files:**
- Multiple modules reference `namespaceSelector.matchLabels.name = "ingress-system"`:
  - `kubernetes/modules/ai-inference.nix` (lines 1355-1356, 1491-1492)
  - `kubernetes/modules/monitoring.nix` (lines 604-605)
- No module creates this namespace.

**Fix:**
Add a Namespace definition to `kubernetes/modules/common.nix` or `kubernetes/modules/infrastructure.nix`:

```nix
none.Namespace.ingress-system = {
  metadata.labels = {
    name = "ingress-system";
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
};
```

**Risk:** None — adding a namespace definition is idempotent.

**Status:** [ ] Pending

---

## Phase 2: High Priority

### 2.1 — Configure alert notification channels

**Files:**
- `kubernetes/modules/monitoring.nix` — AlertManager config (lines 1464-1493)
- `kubernetes/modules/monitoring.nix` — alert-webhook deployment (placeholder, runs `sleep infinity`)

**Problem:**
AlertManager has `receiver: 'log-only'` — all alerts go to stdout only. The `alert-webhook` deployment is a `sleep infinity` placeholder. Critical infrastructure alerts (OOM, etcd, node down) have **zero notification path**.

**Implementation:**
1. Replace the `alert-webhook` deployment with a real webhook handler (Discord, Slack, or a simple webhook to an agent channel)
2. Update AlertManager config with real receiver:

```nix
# In monitoring.nix — receiver section
receivers:
  - name: 'alert-webhook'
    webhook_configs:
      - url: 'http://alert-webhook.monitoring.svc.cluster.local:9093/alert'
        send_resolved: true
  - name: 'log-only'
    # Keep as fallback
```

3. For a quick start: deploy a simple Discord webhook sidecar or reuse the existing `alert-webhook` deployment with actual webhook logic.

**Recommended approach:** Create a simple systemd service on nexus or zephyr that reads AlertManager webhooks and forwards to a notification channel. This avoids needing a full K8s deployment change.

**Risk:** Low — adding notification receivers doesn't affect existing alert routing.

**Status:** [ ] Pending

---

### 2.2 — Zephyr OOM mitigation: move workloads off Zephyr

**Files:**
- `hosts/zephyr/services.nix` — all zephyr services
- `kubernetes/modules/llama-servers.nix` — zephyr GPU deployments

**Problem:**
Zephyr (31GB RAM) runs: k3s server+etcd, NFS server, both GPU inference models, mining, desktop, gaming. This is the cluster's single point of failure — an OOM kills etcd quorum, NFS exports (remotes can't rebuild), all local inference.

**Mitigations (in order of impact):**

1. **Move k3s server role to Nexus** — Nexus has 46GB and is already a server. Zephyr could become an agent. This reduces control-plane risk.
   - File: `hosts/zephyr/services.nix` → `services.k3s-cluster.role = "agent"`
   - Requires: ensuring Nexus is the primary etcd member

2. **Reduce idle GPU deployments** — 5 of 7 Zephyr GPU deployments are `replicas=0`. The Nix definitions still consume memory for container image pulls and ConfigMap storage. Consider removing dead deployments entirely and scaling up via automation when needed.

3. **Add zram/zswap pressure monitoring** — Already has zram enabled. Consider adding earlyoom with more aggressive thresholds for Zephyr specifically.

**Note:** Full K8s HA requires 3 etcd members. Currently Zephyr + Nexus are servers (2/3 needed). Adding Sentry as a third server would allow Zephyr to fail without losing etcd quorum.

**Status:** [ ] Pending — REQUIRES DECISION ON ROLE CHANGES

---

### 2.3 — Add missing ABI/port discovery for the gateway manifest

**Files:**
- `kubernetes/default.nix` — currently unmapped ai-inference/llama-servers

**Problem from 1.2 continued:**
Even after mapping, there's a structural concern: the `ai-inference` module references `cluster.hosts.sentry.ip` and `cluster.hosts.nexus.ip` hardcoded in ConfigMaps. These need to be kept in sync with any IP changes.

**Quick fix:** Already using `cluster.nix` as a single source of truth — this is correct. Just needs the manifest mapping resolved.

---

## Phase 3: Medium Priority

### 3.1 — Single-replica HA audit

**Problem:**
Nearly all deployments are `replicas=1` with no pod anti-affinity:
- Loki, Mimir, Tempo (StatefulSets with PVCs — hard to make HA)
- Grafana, Casdoor, SearXNG, n8n, Open WebUI (Deployments — could be HA)
- Kubernetes MCP Server (already has nexusPreferredAffinity)

**Quick wins:**
- **Grafana**: Already has podAntiAffinity defined. Add `replicas=2` and remove explicit `nodeSelector` to allow scheduling on nexus as fallback. The emptyDir for data is ephemeral anyway.
- **Casdoor**: Can run 2 replicas with shared Postgres backend. Remove `nodeSelector` pinning.
- **SearXNG**: Stateless, can scale to 2+ replicas with shared Redis.
- **Open WebUI**: Currently pinned to sentry. Add nexus as failover target.

**Files affected:** Multiple `kubernetes/modules/*.nix` — search for `replicas = 1` and `nodeSelector` / `nodeName`.

**Priority:** Depends on uptime requirements. If cluster is for personal use, single-replica is acceptable.

**Status:** [ ] Pending — REQUIRES UPTIME REQUIREMENT DECISION

---

### 3.2 — Stub service cleanup

**Problem:**
Two deployments are stubs/placeholders that do nothing useful:

1. **Knowledge Fabric API** (`ai-inference.nix` lines 862-990):
   - Runs `python:3.12-slim` with an inline Python script returning `{"results": []}`
   - The comment says "RRF middleware runs in gateway"
   - Either implement properly or remove the deployment + service

2. **Privacy Filter** (`privacy-filter.nix`):
   - Full namespace, deployment, service defined
   - Gateway has `PRIVACY_FILTER_ENABLED = "false"`
   - Container image is `python:3.12-slim` — the actual `privacy-filter` package from `packages/privacy-filter.nix` exists but is not used in the container

**Recommendation:** Remove the Knowledge Fabric API stub (it's confusing to maintainers) and either enable privacy filter or remove it.

```bash
# Files to modify/remove:
# - kubernetes/modules/ai-inference.nix: Deployment/Service knowledge-fabric-api
# - kubernetes/modules/privacy-filter.nix: entire file (if removing)
```

**Risk:** Low — both are inactive code paths.

**Status:** [ ] Pending

---

### 3.3 — Replace _latest container images

**Files to audit:**
- `kubernetes/modules/ai-inference.nix` — qdrant image (`docker.io/qdrant/qdrant:v1.17.1` — this is OK, has version)
- `kubernetes/modules/llama-servers.nix` — scratch image (`ghcr.io/lillecarl/nix-csi/scratch:1.0.1` — OK, versioned)
- `kubernetes/modules/host-services.nix` — scratch image (OK)
- `kubernetes/modules/infrastructure.nix` — kubernetes-mcp (`:latest-linux-amd64` — see 0.3)
- `kubernetes/modules/monitoring.nix` — all images pinned with versions (GOOD)
- `kubernetes/modules/searxng.nix` — check image tag
- `kubernetes/modules/haven.nix` — `ghcr.io/ancsemi/haven:3.1.1` (OK, versioned)

**Action:** Confirm all external images are version-pinned (not `:latest`). Only the kubernetes-mcp image uses `:latest`.

**Status:** [ ] Pending (depends on 0.3)

---

### 3.4 — Improve Alloy DaemonSet coverage

**Files:**
- `kubernetes/modules/monitoring.nix` — Alloy DaemonSet (lines 1212-1338)

**Problem:**
The Alloy DaemonSet has tolerations for control-plane taint but the DaemonSet isn't guaranteed to run on all nodes. Current tolerations:
```nix
tolerations = [
  { key = "node-role.kubernetes.io/control-plane"; effect = "NoSchedule"; }
  { key = "node-role.kubernetes.io/master"; effect = "NoSchedule"; }
];
```

Missing tolerations for `workstation` (zephyr) and `interactive` (zephyr) taints. Without these, Alloy doesn't run on zephyr, so zephyr's logs/metrics aren't collected.

**Fix:**
```nix
tolerations = [
  { operator = "Exists"; }  # Tolerate all taints — Alloy should run everywhere
];
```

**Risk:** Low — Alloy is designed as a cluster-wide log/metric collector.

**Status:** [ ] Pending

---

## Phase 4: Lower Priority / Nice-to-Have

### 4.1 — Clean up dead llama-server variants

**Files:**
- `kubernetes/modules/llama-servers.nix`

**Problem:**
7 deployments target the RTX 3090 on Zephyr. Only 1 is active (`llama-server-zephyr-3090-moe`). The remaining 6 are `replicas=0`:
- `llama-server-zephyr` — legacy, port 1237
- `llama-server-zephyr-3090-dense` — port 1238
- `dflash-zephyr-3090` — port 1239
- `llama-server-zephyr-3090-ornstein` — port 1237
- `llama-server-zephyr-3090-hermes` — port 1238
- `llama-server` (in ai-inference.nix) — nexus CPU, port 8080

**Recommendation:** Remove deployments that are no longer planned for active use. Keep only:
- `llama-server-zephyr-3090-moe` (active)
- `llama-qwen-vllm-zephyr-3060ti` (active)
- `llama-server-sentry` (future use)

Move dead variants to an `archive/` module or delete them. They add maintenance burden and confusion.

**Risk:** Low — all are `replicas=0`. Removing definitions only affects future deployments.

**Status:** [ ] Pending

---

### 4.2 — Fix flake lock sync

**Files:**
- `hosts/nexus/configuration.nix` (line 70-71)
- `hosts/sentry/configuration.nix` (line 77-78)
- `hosts/forge/configuration.nix` (line 60)

**Problem:**
```nix
services.flake-lock-sync.enable = lib.mkForce false;
systemd.timers.flake-lock-sync.enable = false;
```

Set on all remote hosts. This means only zephyr updates flake locks. Remote hosts can have stale inputs if they ever rebuild independently.

**Fix:** Enable on at least nexus (which is a server with etcd). Or accept this as intentional (document why).

**Status:** [ ] Pending

---

### 4.3 — GPU-aware autoscaling

**Problem:**
Only CPU/memory HPA exists (for ai-inference-gateway). GPU workloads have fixed replicas. When inference demand spikes, idle GPU capacity (the 6 `replicas=0` deployments) stays idle.

**Future possibility:**
Add DCGM exporter to monitoring stack, then create HPA based on custom GPU metrics:
```yaml
metrics:
  - type: Pods
    pods:
      metric:
        name: nvidia_gpu_utilization
      target:
        type: AverageValue
        averageValue: 50
```

This would require:
1. Deploying DCGM exporter DaemonSet on NVIDIA nodes
2. Adding GPU metrics to Prometheus/Mimir
3. Creating HPAs for each inference deployment

**Status:** [ ] Future — not in scope for current iteration

---

## Execution Order

```
Phase 0 — Quick Wins (do first, any order)
├── 0.1 Fix Grafana MCP credentials
├── 0.2 Remove hardcoded n8n password
└── 0.3 Pin kubernetes-mcp image tag

Phase 1 — Critical Fixes (must do before next deploy)
├── 1.1 Fix Sentry port mismatch
├── 1.2 Map ai-inference + llama-servers manifests
│   └── REQUIRES: Cluster diagnostic first
└── 1.3 Create ingress-system namespace

Phase 2 — High Priority (next deploy cycle)
├── 2.1 Configure alert notifications
├── 2.2 Zephyr OOM mitigation
│   └── REQUIRES: Decision on role changes
└── 2.3 Verify gateway manifest mapping (follow-on from 1.2)

Phase 3 — Medium Priority
├── 3.1 Single-replica HA audit
│   └── REQUIRES: Uptime requirement decision
├── 3.2 Stub service cleanup (knowledge-fabric, privacy-filter)
├── 3.3 Verify no :latest image tags
└── 3.4 Fix Alloy DaemonSet tolerations

Phase 4 — Lower Priority
├── 4.1 Clean up dead llama-server variants
├── 4.2 Fix flake lock sync
└── 4.3 GPU-aware autoscaling (future)
```

## Pre-requisites

Before starting Phase 1.2, run:

```bash
# On zephyr or any k3s server:
kubectl get ns ai-inference  # Does the namespace exist?
kubectl get deployments -n ai-inference  # Are the workloads running?
kubectl get pods -n ai-inference  # Check pod status

# Check which k8s-nix-deploy manifest is active:
ssh zephyr "systemctl cat k8s-nix-deploy | grep manifestPackage"
# Expected: one of 'combined', 'small', or a different path

# Check all hosts:
for h in zephyr nexus forge sentry; do
  echo "=== $h ==="
  ssh $h "systemctl is-active k8s-nix-deploy 2>/dev/null || echo 'not installed'"
done
```

## Verification

After all changes:

```bash
just check                    # Nix flake check
nix build .#kubernetes.small.manifestYAMLFile  # Verify manifests compile
nix build .#kubernetes.ai-inference.manifestYAMLFile
nix build .#kubernetes.llama-servers.manifestYAMLFile
kubectl get pods -A -o wide   # All pods running
kubectl get networkpolicies -A  # All network policies applied
kubectl get deployments -A | grep 0/0  # Should be minimal
```

## Rollback

Each change is scoped to specific files. Rollback per-file:

```bash
git checkout <file>  # Revert individual file
just deploy <host>   # Re-deploy affected host
```

For manifest changes:
```bash
nix run .#k8s-deploy  # Redeploy K8s manifests
```

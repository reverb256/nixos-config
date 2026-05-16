# NixOS Cluster - Claude Code Context

> **⚠️ Cluster conventions, safety rules, deployment workflow, and code style are in `AGENTS.md`.**
> This file covers NixOS basics, K8s troubleshooting, and infrastructure details NOT in AGENTS.md.

## ⚠️ CRITICAL: THIS IS NIXOS

**This is NOT a typical Linux distribution.** This is **NixOS** - a purely declarative Linux distribution where the entire operating system configuration is defined in `/etc/nixos/` and rebuilt via `nixos-rebuild switch`.

### 🔴 MANDATORY: NixOS Configuration Rules

**✅ CORRECT (Declarative):**
- Edit `/etc/nixos/configuration.nix` or `/etc/nixos/modules/*.nix`
- Run `nixos-rebuild switch` to apply changes
- All system state defined in Nix expressions (reproducible, rollback-capable)

**❌ FORBIDDEN (Imperative):**
- **NEVER** install packages with `nix-env -iA package` (breaks declarative model)
- **NEVER** modify `/etc/nix` directly (it's the Nix store - immutable, managed by Nix)
- **NEVER** use `systemctl start/enable` for persistent services (use NixOS config instead)
- **NEVER** edit files in `/etc` outside of NixOS management (won't survive rebuilds)

**Consequences of Breaking These Rules:**
- System becomes unreproducible (declarative + imperative = chaos)
- Rollbacks break (imperative changes can't be rolled back)
- Configuration drift (hard to maintain, impossible to debug)
- Deployments fail (NixOS expects all state in configuration)

---

### NixOS Declarative Model (MANDATORY)

**ALL system changes MUST go through NixOS configuration:**

| Action | ✅ CORRECT (NixOS) | ❌ WRONG (Imperative) |
|--------|-------------------|---------------------|
| Install packages | Edit `environment.systemPackages` in config.nix | `nix-env -iA package` |
| Enable services | Edit `services.<name>.enable = true` in config.nix | `systemctl enable <service>` |
| Start services | `nixos-rebuild switch` (starts enabled services) | `systemctl start <service>` |
| Create users | Edit `users.users.<name>` in config.nix | `useradd <name>` |
| Configure system | Edit `/etc/nixos/modules/*.nix` | Edit `/etc/<files>` directly |
| Apply changes | `nixos-rebuild switch` or `just deploy` | Direct system modifications |

### Emergency Overrides (RARE)

**Only use these if NixOS config is broken and you need SSH access:**
```bash
# TEMPORARY service start (won't survive reboot)
systemctl start sshd

# ONE-OFF commands (no persistent state)
systemctl daemon-reload
systemctl restart kube-apiserver  # Restart control plane (temporary)
```

**After emergency fix:** IMMEDIATELY update NixOS config to match running state.

### NixOS Store (/nix vs /etc/nixos)

| Path | Purpose | Mutable? | Managed By |
|------|---------|----------|-----------|
| `/etc/nixos/` | **NixOS configuration** (source code) | ✅ Yes | You (edit files) |
| `/nix` or `/etc/nix` | **Nix store** (built packages) | ❌ No | Nix (immutable) |
| `/nix/var/nix/profiles/system-*` | **System generations** | ❌ No | NixOS (read-only) |

- `/etc/nixos/` = Source code (like `/usr/src/linux`)
- `/nix` = Binary store (like `/usr/bin` but immutable)
- **NEVER** edit `/nix` directly (it's rebuilt from `/etc/nixos/`)

### NixOS Generations and Rollback

**Every `nixos-rebuild switch` creates a new generation:**

```bash
nixos-rebuild list-generations        # View all generations
nixos-rebuild rollback                # Rollback to previous generation
nix-collect-garbage -d                # Delete old generations (cleanup)
```

**Boot Menu:** GRUB2 shows all generations (can boot into any previous one). Useful for disaster recovery.

---

## COMMANDS

```bash
just check             # Validate flake (quick, no build)
just check-nfs         # Verify NFS mount health on all hosts
just build             # Build configuration for local host
just switch            # Apply to local host (auto-pauses CPU mining)
just deploy            # Deploy to all hosts via Colmena (NFS-based, no sync)
just deploy <host>     # Deploy to specific host (zephyr|nexus|forge|sentry)
just status            # Show cluster status
```

### Kubernetes Commands
```bash
kubectl get nodes                        # Node status
kubectl get pods --all-namespaces        # All pods
kubectl get pv,pvc -A                    # Persistent volumes
just cluster-status                      # Host + K8s status combined
```

---

## KUBERNETES TROUBLESHOOTING

### Common Issues & Quick Fixes

**Issue: Pods stuck in ContainerCreating or ImagePullBackOff**
```bash
kubectl describe pod <pod-name> -n <namespace>  # Check events
kubectl logs <pod-name> -n <namespace>          # Check logs
```

**Issue: Pods not scheduling (Insufficient resources)**
```bash
kubectl describe nodes | grep -A 5 "Allocated resources"  # Check resource usage
kubectl top pods -A                                         # Check pod resource usage
```

**Issue: GPU resources unavailable (nvidia.com/gpu)**
```bash
# Check GPU registration
kubectl describe node <node-name> | grep nvidia.com/gpu

# Check nvidia-device-plugin logs
kubectl logs -n kube-system -l name=nvidia-device-plugin

# If GPUs show 0 capacity: Restart kubelet on that node
ssh <node> "sudo systemctl restart kubelet"
```

**Issue: Too many zombie pods (ContainerStatusUnknown)**
```bash
# Count unknown pods
kubectl get pods -A --field-selector=status.phase==Unknown

# Bulk delete failed pods
kubectl delete pods -A --field-selector=status.phase==Failed --force --grace-period=0
```

**Issue: Deployment creating hundreds of replicas**
```bash
# Check deployment replica count
kubectl get deployment <deployment-name> -n <namespace> -o jsonpath='{.spec.replicas}'

# Scale down immediately
kubectl scale deployment <deployment-name> -n <namespace> --replicas=0

# Check if using volcano-scheduler (switch to default-scheduler)
kubectl patch deployment <deployment-name> -n <namespace> \
  -p '{"spec":{"template":{"spec":{"schedulerName":"default-scheduler"}}}}'
```

**Issue: kubectl timeout or connection refused**
```bash
# Check API server status
ssh zephyr "sudo systemctl status kube-apiserver"

# Check etcd status (API server backend)
ssh zephyr "sudo systemctl status etcd"

# If both down: Restart in correct order
ssh zephyr "sudo systemctl restart kube-apiserver"  # Auto-recovers etcd dependency
```

### Prevention Measures

**1. Use Default Scheduler for Regular Workloads**
```yaml
spec:
  template:
    spec:
      schedulerName: default-scheduler  # NOT volcano-scheduler
```

**2. Set Explicit Resource Limits**
```yaml
resources:
  requests:
    cpu: "2"
    memory: "1Gi"
  limits:
    cpu: "4"      # Must comply with LimitRange
    memory: "3Gi"
```

**3. Prevent Replica Explosions**
```yaml
spec:
  replicas: 1                     # ALWAYS set explicit count
  revisionHistoryLimit: 2         # Limit old replica sets
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 0                 # Don't create extra pods
      maxUnavailable: 1
```

**4. Run All GPU Workloads in Kubernetes**
- No external systemd GPU miners (bypasses K8s resource awareness)
- All GPU processes visible to nvidia-device-plugin
- Prevents "OutOfnvidia.com/gpu" even when GPUs appear free

**5. Apply Secrets Before Deployments**
```bash
# Always apply secrets first
kubectl apply -f kubernetes-manifests/n8n/
kubectl apply -f kubernetes-manifests/glitchtip/

# Then deploy workloads
kubectl apply -f kubernetes-manifests/ai-inference/
```

**6. Control plane restart order (if absolutely necessary)**
1. kube-apiserver (last to stop, first to start)
2. kube-scheduler
3. kube-controller-manager
4. kubelet
5. **NEVER restart etcd** unless absolutely necessary (breaks cluster)
   - etcd SIGTERM → kube-apiserver hangs → cascade failure

---

## AI INFRASTRUCTURE

### Sovereign Service Mesh — AI Gateway (Central Bus)

**Status:** ✅ OPERATIONAL — All AI/ML workloads route through AI Gateway

**Gateway Service:** `ai-inference-gateway.ai-inference.svc.cluster.local:8080`
**ClusterIP:** 10.15.67.242:8080
**Location:** K8s Deployment on Nexus

**Endpoints:**
- `/health` — Health check
- `/v1/models` — Model listing
- `/v1/chat/completions` — OpenAI-compatible API
- `/search` — SearXNG raw web search
- `/search/hybrid` — RAG + SearXNG with RRF
- `/search/agent` — Intent detection + summarization
- `/rag/search` — Qdrant semantic search
- `/v1/embeddings` — BGE-M3 embedding generation

**Architecture:** Bus-style service mesh with AI Gateway as central orchestrator
- **Qdrant** — Vector database for semantic search
- **SearXNG** — Web search for current information
- **QueryIntent routing** — Automatic query classification
- **CrossEncoder reranking** — Result quality optimization

**Documentation:** See `docs/SOVEREIGN-SERVICE-MESH-STATUS.md` for complete details.

### Multi-GPU Model Distribution

| GPU Location | GPU | VRAM | Model | Port | Status |
|--------------|-----|------|-------|------|--------|
| **Zephyr RTX 3090** | CUDA 1 | 24GB | Qwen3.6-35B-A3B (MoE) | 1237 | ✅ Systemd |
| **Zephyr RTX 3060 Ti** | CUDA 0 | 8GB | Qwen3.5-2B-AWQ (vLLM+TQ) | 8040 | ✅ Systemd |
| **Sentry AMD RX 5600 XT** | Vulkan | 6GB | Qwen3.5-4B-Q4_K_M | 1235 | ✅ K8s |

**Note:** Zephyr uses systemd llama-server services instead of K8s for better GPU isolation and gaming integration.

### llama.cpp Custom Patches

**TurboQuant Build:** `pkgsWithOverlay.llama-cpp-turboquant`
- Custom optimizations for flash attention, KV cache compression
- IQ4_NL and turbo4 cache types for reduced VRAM usage
- DeepSeek reasoning format support

---

## SUPPLY CHAIN SECURITY

All software on this cluster has supply chain protections enforcing a 7-day cooling period on newly published packages and images.

### Package Manager Cooldowns (7-day age gate)

| Ecosystem | Config | Module |
|-----------|--------|--------|
| **npm** | `~/.npmrc` → `min-release-age=7` | `services.supply-chain-cooldowns` |
| **pnpm** | Same `~/.npmrc` (respects npm config) | `services.supply-chain-cooldowns` |
| **bun** | `~/.bunfig.toml` → `minimumReleaseAge = "7d"` | `services.supply-chain-cooldowns` |
| **uv (Python)** | `~/.config/uv/uv.toml` → `exclude-newer = "7 days"` | `services.supply-chain-cooldowns` |

### Container Image Security

- **Image policy**: Rejects unsigned images by default; allows docker.io/library, ghcr.io, quay.io, localhost
- **No `:latest` tags**: All images pinned to specific versions
- **Trivy scanning**: Weekly vulnerability scan (`services.container-scanning.enable = true`)
- **K8s admission policy**: `kubernetes-manifests/security/deny-latest-tag.yaml` blocks `:latest` tags

### Flake Input Age Validation

`modules/services/auto-update.nix` validates that nixpkgs inputs are older than 7 days before auto-updating.

### GitHub Actions Pinned to Commit SHAs

All CI workflows (`.github/workflows/`) pin actions to immutable commit SHAs instead of mutable version tags.

---

## Central SSO Authentication

> **Full details in `AGENTS.md` → "Central SSO Authentication" section.**

Architecture: Casdoor OIDC (auth.lan) → oauth2-proxy (central-auth.service) → Caddy forward_auth.
Deployed on Zephyr + Nexus. Do NOT deploy oauth2-proxy as K8s sidecars.
Native OIDC audit completed 2026-05-14: Grafana, AI Gateway, Gitea, Open WebUI wired to Casdoor.
Haven, MC, Kagent have no native OIDC — proxy auth correct.

---

## GITHUB ISSUES WORKFLOW (MANDATORY)

**ALL non-trivial work MUST be tracked in GitHub Issues.**

### When to Create an Issue

- Any task taking >15 minutes
- Security hardening work (P1)
- Features or polish (P2)
- Bug fixes with cross-file impact
- Module expansion or data integration
- Infrastructure changes

### Workflow

```bash
# Before starting work — check for existing issues
gh issue list --repo reverb256/nixos-config
gh issue list --repo reverb256/maplespike

# Create new issue if needed
gh issue create --repo <repo> --title "Title" --body "Description" --label "p1,p2"

# Claim work
gh issue edit --repo <repo> <number> --assignee "@me"

# Mark in progress
gh issue edit --repo <repo> <number> --add-label "in-progress"

# Reference in commits ( closes #<number> auto-closes)
git commit -m "feat: description

Fixes #<number>"

# Close when done
gh issue close --repo <repo> <number>
```

### Labels

| Label | Color | Meaning |
|-------|-------|---------|
| `p1` | orange | High priority — security, stabilization |
| `p2` | blue | Medium priority — features, polish |
| `security` | red | Security-related |
| `k8s` | cyan | Kubernetes work |
| `frontend` | yellow | UI/portal work |
| `module` | teal | Data module work |

### Repositories

| Repo | Purpose | Issues Enabled |
|------|---------|----------------|
| `reverb256/nixos-config` | NixOS cluster, K8s manifests | ❌ Disabled — use MapleSpike |
| `reverb256/maplespike` | MapleSpike app, data modules | ✅ Enabled — ALL issues here |

**IMPORTANT:** Create ALL issues in `maplespike` repo, even for cluster work.

---

## REFERENCE DOCUMENTS

| Document | Purpose |
|----------|---------|
| `AGENTS.md` | **Primary reference** — cluster conventions, safety rules, code style, deployment |
| `INFRASTRUCTURE-AUDIT.md` | Live cluster state and issues |
| `ROADMAP.md` | Kubernetes migration plan |
| `kubernetes-manifests/PREVENT_POD_EXPLOSION.md` | Pod explosion prevention rules |
| `skills/cluster-conventions/SKILL.md` | Full convention reference with templates |

---

**Version**: 8.0 | **Updated:** 2026-05-02
**Changes**: Deduplicated with AGENTS.md — this file now covers NixOS basics + K8s troubleshooting + AI infrastructure only. Cluster conventions moved to AGENTS.md.

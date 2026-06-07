# Infrastructure Connectivity Audit & Cleanup Plan

**Created:** 2026-04-17
**Context:** Full audit of all AI infra, NixOS infra, and /data/projects/ connectivity
**Status:** Brainstorm — awaiting decisions before execution

---

## Full Connectivity Map

### Layer 1: LIVE — Wired into running cluster

**NixOS Flake Inputs (7 projects):**

| Input | Project | Module Imported | Used By | Package Consumed |
|---|---|---|---|---|
| `ai-gateway` | ai-inference-gateway | `nixosModules.default` | ALL hosts | `container` (K8s image) |
| `compute-market` | compute-market | `nixosModules.default` | ALL hosts | `xmrig-alpine-image`, `xmrig-proxy-alpine-image` |
| `gpu-proxy` | gpu-proxy | `nixosModules.default` | ALL hosts | (none consumed yet) |
| `mcp-registry` | mcp-registry | `nixosModules.default` | ALL hosts | (none consumed) |
| `caddy-ingress` | caddy-ingress | `nixosModules.{caddy,caddy-common}` | ALL hosts | `caddy-with-modules`, `caddy-ingress-image` |
| `knowledge-fabric` | knowledge-fabric | **NOT imported** | — | **NOT consumed** |
| `llama-turboquant` | llama-cpp-turboquant | **NOT imported** (correct — package only) | — | `llama-cpp-turboquant` via overlay |

**K8s EasyKubenix (auto-deployed via kluctl):**

| Namespace | Workloads | Image Source | Nodes |
|---|---|---|---|
| `ai-inference` | gateway, qdrant, redis, open-webui, grafana, llama-cpp-qwen | `ai-gateway.container`, `qdrant:v1.13.4`, `redis:7`, upstream | nexus, zephyr, sentry |
| `search` | searxng | `searxng/searxng:latest` | nexus |

**K8s Static Manifests (manually applied):**

| Directory | Workloads | Nodes | Deploy Script? |
|---|---|---|---|
| `mining/` | xmrig-zephyr/nexus/sentry, gpu-miner-forge/zephyr, xmrig-proxy | all 4 | `deploy-mining-k8s.sh` |
| `n8n/` | n8n | nexus | unknown |
| `llama-cpp/` | llama-cpp (pvc + service endpoints) | nexus, forge | unknown |
| `spacebot/` | spacebot | unknown | unknown |
| `monitoring/` | prometheus-stack | unknown | unknown |
| `calico/` | calico CNI | all | unknown |

**NixOS Systemd (project-connected):**

| Service | Host(s) | Project Input |
|---|---|---|
| `ai-inference` | zephyr, nexus, forge, sentry | `ai-gateway` |
| `compute-market` | zephyr, forge | `compute-market` |
| `mining` (lolMiner, XMRig) | zephyr, nexus, forge, sentry | `compute-market` |
| `gaming-mining-coordinator` | zephyr, forge | `compute-market` |
| `gpu-proxy-cpp` | forge | `gpu-proxy` |
| `xmrig-proxy` | zephyr | `compute-market` |
| `mcp-servers` | ALL hosts | `mcp-registry` |
| `hermes-agent` | nexus | `hermes-agent` (external) |
| `caddy` | ALL hosts | `caddy-ingress` |

### Layer 2: PARTIALLY CONNECTED

**`knowledge-fabric`** — Flake input declared but module never imported. Runs as pi extension, not NixOS service. The flake input declaration is dead weight.

**`llama-turboquant`** — Flake input declared, package consumed via overlay + K8s easykubenix. Also has static manifests in `kubernetes-manifests/llama-cpp/` (duplicate definition).

### Layer 3: TOTALLY DISCONNECTED

| Project | Has Flake | Has NixOS Module | Has K8s Manifest | Why Disconnected |
|---|---|---|---|---|
| `searxng-cluster` | YES | YES | YES | Cluster uses easykubenix module with upstream image |
| `synapse` | YES | YES | NO | Module never imported. Nextcloud creates empty dirs. |
| `astral-key` | YES | YES (`nixos-module.nix`) | NO | Module never imported anywhere |
| `local-llm-stack` (infra) | NO | YES | NO | Superseded by hermes-agent + K8s llama-servers |
| `qwen3.5-infrastructure-brain` (infra) | NO | NO | NO | Phase 2 prototype, depends on pi-mono fork |
| `kb-mcp` (manifest only) | — | — | YES | Explicitly DELETED in NixOS config, manifest orphaned |

### Layer 4: BY DESIGN (no infra expected)

| Project | Reason |
|---|---|
| `reverb256.github.io` | GitHub Pages (external) |
| `awip` | API specification |
| `frostbite-gazette` | GitHub Pages |
| `civic-intel` | GitHub Pages |
| `llm-benchmarks` | Utility scripts, no flake |
| `pi-pipeline` | Pi extension, installed via install.sh |
| All `clients/` | External hosting |
| All `forks/` | Upstream code |

---

## Duplicate Deployment Definitions

| Service | EasyKubenix Source | Static Manifest Source | Conflict? |
|---|---|---|---|
| **ai-inference** | `kubernetes/modules/ai-inference.nix` | `kubernetes-manifests/ai-inference/` (~15 files) | **YES** |
| **llama-cpp** | `kubernetes/modules/llama-servers.nix` | `kubernetes-manifests/llama-cpp/` (6 files) | **YES** |
| **mining** | (none) | `kubernetes-manifests/mining/` | NO |
| **searxng** | `kubernetes/modules/searxng.nix` | (none) | NO |

---

## Cleanup Plan

### Category A: DELETE — Clearly superseded, no future value

**A1. `local-llm-stack/` (infra/)**
- Replaced by: `hermes-agent` + `lm-studio-headless.nix` + K8s llama-servers
- Old `/data/@projects/` paths throughout
- NixOS module, shell scripts — all superseded
- Action: Delete entire directory

**A2. `kb-mcp/` (kubernetes-manifests/)**
- Replaced by: `knowledge-fabric` (as pi extension)
- NixOS config explicitly says `# kb-mcp-server: DELETED`
- `localhost/kb-mcp:latest` image doesn't exist
- Action: Delete directory

**A3. `knowledge-fabric/` (kubernetes-manifests/)**
- Never deployed as K8s — runs as pi extension instead
- `localhost/knowledge-fabric:latest` image likely doesn't exist
- Action: Delete directory

**A4. `searxng-cluster/` (own/)**
- Replaced by: `kubernetes/modules/searxng.nix` (easykubenix) using upstream image
- Extracted project's Docker Compose + K8s YAML are dead code
- Action: Delete entire directory (or strip to just flake shell for dev)

**A5. Ghost iteration manifests in `kubernetes-manifests/ai-inference/`**
- ~10 iteration artifacts: `gateway-deployment-diagnostic.yaml`, `-refactored.yaml`, `-simple.yaml`, `-yunikorn-fixed.yaml`, `-yunikorn.yaml`, `-external-service.yaml`, `embed-server.yaml`, `istio-mesh.yaml`, `ai-inference-clean.yaml`, `apply-gateway-fix.sh`
- Real deployment handled by easykubenix
- Action: Delete iteration files, keep only `helm/` (if used) + `gateway-service.yaml` (if referenced)

**A6. `kubernetes-manifests/archive/`**
- `backup-20260322/` has old xmrig configs (2.4K lines)
- `coredns.yml`, `gateway/` — unclear if needed
- Action: Audit what's referenced, delete the rest

**A7. Old commented-out module files in `modules/default.nix`**
These are commented out with migration notes:
- `./mining/mining-plasmoid.nix` (2 files left: README + plasmoid)
- `./mining/*` (6 commented lines)
- `./compute-market/default.nix` (1 commented line)
- `./services/ai-inference/default.nix` (commented — directory may be empty)
- `./services/mcp-servers.nix` (commented — file still exists)
- `./services/caddy.nix`, `./services/caddy-common.nix` (commented)
- Action: Delete source files + directories, remove comments

**A8. `qwen3.5-infrastructure-brain/` (infra/)**
- Phase 2 prototype, never completed
- Depends on `pi-mono` fork for `@mariozechner/*` packages
- Action: Delete (if not active development) or archive

### Category B: MIGRATION INCOMPLETE

**B1. `knowledge-fabric` flake input — declared, never imported**
- Runs as pi extension, not NixOS service
- If pi extension is final form: remove from `flake.nix` inputs
- If NixOS service is planned: import module in `common-modules-list.nix`
- **DECISION NEEDED**

**B2. Duplicate ai-inference + llama-cpp definitions**
- Easykubenix is canonical (per ROADMAP.md)
- Static manifests may have unique configs (llama-cpp forge service endpoints)
- Action: Migrate any unique static configs into easykubenix, then delete static manifests

**B3. `kubernetes-manifests/llama-cpp/` — check for unique configs**
- `10-service-nexus.yaml`, `11-service-forge.yaml`, `20-cluster-loadbalancer.yaml`
- These service routing configs may not be in easykubenix `llama-servers.nix`
- Action: Verify easykubenix coverage, migrate gaps, delete

### Category C: NEVER CONNECTED — Future or dead?

**C1. `synapse/` (own/)**
- Has NixOS module, Dockerfile, Tauri app (819 files)
- Never imported. Nextcloud creates empty dirs for it.
- **DECISION NEEDED**: Deploy, archive, or delete?

**C2. `astral-key/` (own/)**
- Has `nixos-module.nix`, Dockerfile, Rust backend (95 files)
- Never imported. ~95% complete. Has Vaultwarden integration.
- **DECISION NEEDED**: Deploy? Seems like it should be — Vaultwarden is live.

**C3. `spacebot/` (kubernetes-manifests/)**
- Has full deployment: deployment, configmap, ingress, PVC, PV, secrets, service, servicemonitor
- No deploy script. Unclear if running.
- **DECISION NEEDED**: Live? If yes, needs deploy script. If no, archive.

### Category D: DOC CLEANUP

**D1. `flake.nix` extraction comment block (lines 69-73)**
- Says "Migration in progress (see EXTRACTION-PLAN.md)"
- Stale — 7 of 7 intended inputs ARE active
- Action: Update to reflect reality

**D2. `README.md` extracted projects table**
- Lists 8 projects including `searxng-cluster` (not wired)
- Action: Remove searxng-cluster or add "not wired" note

**D3. `ROADMAP.md` — 844 lines, very stale**
- References "Kubernetes v1.35.0" (actually K3s v1.34.x)
- Says "Full Kubernetes via services.kubernetes" but uses K3s
- References phantom `docs/kubernetes/` and `docs/compute-market.md` paths
- Phase 7 says "Remove old systemd services" but old modules still in tree
- Action: Major trim or rewrite

**D4. `modules/services/ai-inference/` directory**
- May be empty (module was migrated to `ai-gateway` input)
- Action: Delete if empty

---

## Execution Order

| Priority | Action | Effort | Risk | Status |
|---|---|---|---|---|
| P0 | Delete `kb-mcp/` + `knowledge-fabric/` K8s manifests | 2 min | Zero | Pending |
| P0 | Delete ghost iteration manifests in `ai-inference/` | 5 min | Zero | Pending |
| P1 | Delete `local-llm-stack/` (infra/) | 2 min | Zero | Pending |
| P1 | Remove `knowledge-fabric` from flake.nix (if pi ext is final) | 2 min | Zero | Pending decision |
| P1 | Delete old commented-out module files + directories | 10 min | Low | Pending |
| P2 | Resolve ai-inference/llama-cpp duplicate definitions | 30 min | Medium | Pending |
| P2 | Delete or archive `searxng-cluster` project | 5 min | Low | Pending |
| P3 | Decide fate of `synapse`, `astral-key`, `qwen3.5-infrastructure-brain` | Discussion | N/A | Pending decision |
| P3 | Decide fate of `spacebot` manifest | Discussion | N/A | Pending decision |
| P3 | Trim ROADMAP.md | 30 min | Zero | Pending |
| P3 | Update `flake.nix` comment block + `README.md` | 5 min | Zero | Pending |

---

## Open Decisions

1. **`knowledge-fabric`** — Is pi extension the final form, or should it be a NixOS service?
2. **`qwen3.5-infrastructure-brain`** — Still active development, or can it be deleted?
3. **`synapse`** — Future deployment planned, or dead project?
4. **`astral-key`** — Future deployment planned? (Vaultwarden auth is live — seems like it should be deployed)
5. **`spacebot`** — Is this actually deployed on K8s? No deploy script found.
6. **Easykubenix vs static manifests** — For ai-inference and llama-cpp, migrate unique static configs into easykubenix then delete statics?

---

## Key Data Points

- `/data/projects/own/` has 16 directories, 12 with flake.nix
- 7 of 12 are wired as active inputs in `/etc/nixos/flake.nix`
- 5 NOT wired: `searxng-cluster`, `synapse`, `reverb256.github.io`, `astral-key`, `awip`
- 4 without flake.nix: `civic-intel`, `frostbite-gazette`, `llm-benchmarks`, `pi-pipeline`
- K8s has two deployment paths: easykubenix (kluctl) + static manifests (kubectl apply)
- Duplicate definitions exist for ai-inference and llama-cpp
- `kubernetes-manifests/` has ~429 YAML files across ~30 directories
- Mining is the only static manifest set with a documented deploy script

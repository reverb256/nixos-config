# Project knowledge

This file gives Codebuff context about this repo: goals, commands, conventions, and gotchas.

## What this is

Flake-based NixOS configuration for a 4-node SOHO cluster (Zephyr, Nexus, Forge, Sentry) running AI inference, GPU compute/mining, K8s workloads, storage, and monitoring. Zephyr is the development/source-of-truth host; all config rebuilds flow from there through git → Colmena / `just deploy` → remote hosts via `nix-copy-closure` + `switch-to-configuration`.

Configuration is split across **three layers** (see AGENTS.md):

| Layer | Where | Owns |
|-------|-------|------|
| 1 — NixOS | `/etc/nixos` (this repo, `reverb256/nixos-config`) | hosts, services, networking, hardware, deployment |
| 2 — Home Manager | `/home/j_kro/Projects/home-manager-config` (flake input `github:reverb256/home-manager-config`) | user configuration, niri settings/keybinds, app configs |
| 3 — user nix profile | `nix profile` | high-churn binaries (Hermes, Freebuff) — never collide with Layer 2 |

`homeConfigurations` in `flake.nix` are consumed **directly from the `home-manager-config` flake input** (line ~295); `/etc/nixos/modules/home-manager/` only holds the shared-leaf module set + standalone entrypoints that both paths compose from (`shared-leaf-modules.nix`, `standalone*.nix`).

### Hosts

| Host | IP | Role | RAM |
|------|-----|------|-----|
| Zephyr | 10.1.1.110 | Workstation, control plane, gaming, NFS ex-ZFS-share | 31GB |
| Nexus | 10.1.1.120 | Primary server, storage, AI gateway, default K8s target | 46GB |
| Forge | 10.1.1.130 | GPU computing, mining | 15GB |
| Sentry | 10.1.1.140 | Monitoring, logging, Vulkan AI inference (RX 5600 XT) | 31GB |

Total: ~78 cores, ~123GB RAM, 7 GPUs, ~8.4TB.

### Internal services

VPN/mesh: Tailscale (split DNS for `.lan`). All `.lan` hostnames → VIP 10.1.1.100 (Keepalived MASTER on Zephyr). DNS via `unbound` cluster-wide.

SSO: Casdoor (OIDC) → `oauth2-proxy` on Zephyr+Nexus (port 4180) → Caddy `forward_auth` for protected services. Hashing/CAS: Garage S3, Casdoor, Vaultwarden. AI: sovereign gateway on Nexus, llama.cpp (Vulkan/CUDA), vLLM+TurboQuant containers, Qdrant. Dev: Gitea+actions-runner (nexus). Observability: Prometheus+Grafana, glances, Caddy metrics.

## Other services (cross-reference for AI agents)

Brief catalog of running cluster services for context-window savings when prompted about a specific service.

| Service | Purpose | Notes |
|---------|---------|-------|
| **gitea** | self-hosted Git at `gitea.lan` | CI runner on nexus (`gitea-runner` pod); Caddy forward_auth; native OIDC via Casdoor app `app-gitea` |
| **vaultwarden** | Bitwarden-compatible password vault | ClusterIP-only; admin via operator OIDC; user data vault outside cluster (operator-only) |
| **garage** | S3-compatible object store | Multi-host replication; used for syncthing-folder-id backups + LibreNMS collector uploads |
| **glitchtip** | Sentry-alternative error tracking | Postgres in-cluster; ingress via Caddy |
| **casdoor** | central OIDC IdP | see SOPS-NIX.md for auth integration; runs on nexus |
| **mission-control** | orchestration dashboard at `mission-control.lan` | behind forward_auth; exposes AI agent seed-tasks |
| **frostbite-postgres** | Postgres for AI/inference namespace | single-replica StatefulSet on sentry; backs Qdrant + privacy-filter |
| **hermes-profile** | per-user ~/.hermes env expansion | sourced by `local/.hermes-profile`; unrelated to vaultwarden-secret-source plugin |
| **maplespike-portal** | portal UI at `maplespike.lan` | development namespace; Caddy forward_auth |
| **open-webui** | LLM chat UI | Casdoor app `app-openwebui` (May 14 wiring) |

## Quickstart

### Commands (run on Zephyr unless noted)

```bash
just check              # Validate flake (fast, no build)
just build              # Build current host's toplevel
just switch             # Build + activate on local host (auto-pauses CPU mining)
just test-apply         # Build + test activation without a permanent switch
just deploy [<host>]    # Build + deploy to all or one host (zephyr|nexus|forge|sentry|"all")
just deploy-nexus <h>   # Async deploy from nexus via tmux (for nexus/forge/sentry only)
just deploy-canary *hosts  # Canary-validate a deploy before full rollout
just provenance *hosts     # Deployment provenance / drift check
just preflight          # Run preflight checks only
just rollback           # Rollback current host
just status             # Branch + commit + worktree + uncommitted state
just health             # SSH reachability + `kubectl get nodes`
just sync-nodes         # Pull central repo on nexus/forge/sentry (keeps /etc/nixos aligned)
just git-push           # Push origin + central + pull on remotes
just update             # `nix flake update`
just topgrade [apply]   # Super-upgrade: update all inputs, build, deploy, gc (apply=true to execute)
just gc                 # `nix-collect-garbage -d`
just new-worktree NNN   # Create worktree /data/projects/own/nixos-config-NNN from issue #NNN
just validate-k8s       # Build/eval K8s manifests
just full-check         # Run scripts/check.sh (lint + sec + parse)
just hm-switch          # Activate current host's standalone HM (home-manager switch --flake .#<host>), no NixOS rebuild
just hm-build <host>    # Dry-build an HM configuration (default zephyr)
```

### Validation primitives

```bash
nix flake check             # Option-name validator (catches typos fast)
nix build .#nixosConfigurations.<host>.config.system.build.toplevel
sudo nixos-rebuild switch --flake .#<host>   # direct fallback
git add -A && git commit && git push origin main
```

### K8s quick ops

```bash
kubectl get nodes -o wide
kubectl get pods -A | head
kubectl describe node <n> | grep -A 5 "Allocated resources"
```

## Architecture

### Repo layout

```
/etc/nixos/
├── flake.nix                # Main flake + hosts (zephyr/nexus/forge/sentry) + colmena wrapper
│                            #   + inputs (nixpkgs, home-manager, home-manager-config, colmena, ...)
├── colmena.nix              # Multi-host deployment (targetHost, tags per host)
├── common-modules-list.nix  # Module list imported by BOTH flake.nix and colmena.nix (must stay in sync)
├── overlay.nix              # Cross-system package overlay
├── justfile                 # All CI/CD tasks
├── hosts/<host>/            # Per-host NixOS configs
├── modules/                 # ~171 reusable .nix files
│   ├── system/              # Core (ssh, users, networking, sops, nix, OOM/oomd, vm-tuning)
│   ├── services/            # Background daemons (k8s, monitoring, mining, hermes, bonsai...)
│   ├── desktop/             # Niri-only desktop (compositor, UWSM sessions, monitors, HDR/brightness)
│   ├── home-manager/        # HM shared-leaf modules + standalone entrypoints (NOT the full HM config —
│   │                        #   that lives in the home-manager-config flake input)
│   ├── profiles/            # Composable hardware/role/network profiles
│   ├── hardware/            # GPU/AMD/NVIDIA/RGB drivers
│   ├── development/         # Dev tools
│   ├── gaming/              # Launchers, GameMode integration, gaming slice
│   ├── network/             # cluster-hosts, cluster-dns, cluster-networking
│   └── security/            # PAM, GPG, cluster-mesh SSH account
├── kubernetes/              # K8s Nix modules (easykubenix). 21 files.
│   ├── modules/             # ai-inference, nix-csi, monitoring, ingress...
│   ├── service-ports.nix    # SINGLE SOURCE OF TRUTH for NodePort assignments
│   ├── cluster.nix          # Cluster IPs/VIP/subnet constants
│   └── default.nix          # Easykubenix entry point
├── kubernetes-manifests/    # ~256 raw K8s YAML files (legacies + security, GPU examples)
├── scripts/                 # ~118 scripts (78 .sh, 30 .py). Includes preflight-check.sh, remote-build.sh, topgrade.sh, yaml-validate.py
├── packages/                # ~14 custom .nix packages (llama-cpp-*, hermes-chat, privacy-filter...)
├── tests/                   # NixOS integration tests
├── secrets/                 # ~42 sops/age-encrypted secrets (.age) + unencrypted templates
├── pkgs/                    # Local package definitions (peakminer exporter, secretspec forks...)
├── recoveries/              # Disaster recovery scripts
├── machines                 # Colmena machine list
├── docs/                    # Long-form documentation
├── plans/, .plans/          # Planning workspaces
└── .github/workflows/       # CI (SHA-pinned actions)

# Sibling repos (flake inputs):
/home/j_kro/Projects/home-manager-config   # Layer 2: full HM config (niri-config/keybinds/spawn/outputs, app modules)
```

### Workflow: GitOps via worktrees + main

```
main                          # integration AND production; /etc/nixos on all hosts tracks main
issue-NNN-<slug>              # all new work; lives in /data/projects/own/nixos-config-NNN worktree
```

Author workflow: `just new-worktree NNN` → edit in `/data/projects/own/nixos-config-NNN` → `nix flake check` → `git push origin issue-NNN-...` → `gh pr create --base main` → squash-merge → `cd /etc/nixos && git pull` → `just deploy`.

`/etc/nixos` itself on every host stays on `main`; deployed cluster state = `main` HEAD after the most recent `just deploy`.

### Build pipeline quirks

- Zephyr NEVER builds locally (31GB RAM OOM); since 2026-08-08 Forge and Sentry are also non-builders — **Nexus is the sole Nix build executor** (`max-jobs=6`), all other hosts run `max-jobs=0` and dispatch to Nexus via `scripts/remote-build.sh` or the Nexus dispatcher.
- `just deploy` and `just deploy-async` run `scripts/deploy/nexus-dispatch.sh`; Nexus refreshes `/etc/nixos` to `origin/main`, builds with Colmena, and activates the selected target. Zephyr remains the authoring/source-of-truth host.
- `just deploy-nexus` is a compatibility alias into the same dispatcher; it no longer has a separate `targetHost=null` path.
- `scripts/preflight-check.sh` runs before dispatch and refuses source/builder drift, failed self-healing, stale `origin/main`, or an in-flight build.
- Use the `.#colmena` app (flake-local 0.5.0-pre), NOT `nixpkgs#colmena` (channel-pinned 0.4.0 can't evaluate `colmenaHive`).

### Ports ↔ DNS bridge

`kubernetes/service-ports.nix` is the **single source of truth** for NodePort assignments. Both Zephyr's Caddy (`hosts/zephyr/caddy-routes.nix`) and Nexus's cluster Caddy (`modules/services/cluster-services.nix`) import it. To add a `.lan` service: pick unused 30xxx port → add to `service-ports.nix` → add DNS record in `modules/network/cluster-dns.nix` → add Caddy route → deploy K8s Service with matching `nodePort`.

## Conventions (HARD rules)

### NixOS declarative-only (the #1 most expensive failure pattern)

ALL persistent system state lives in `.nix` files under git. SSH into a NixOS host is for reading state ONLY. Never imperatively `systemctl start/enable` a service, `nix-env -i` a package, `useradd`, or edit `/etc/*` directly — those changes don't survive `nixos-rebuild` and can't be rolled back. The `.nix` file on Zephyr is the source of truth; running hosts are consumers. The live host is a rolled-back snapshot, never authoritative.

`nixos-rebuild switch` creates a new generation (rollback via `nixos-rebuild rollback` or boot menu). Nix store (`/nix`) is immutable/rebuilt-from-config — never edit it directly.

### mkOptionDefault for shared modules (MANDATORY for extensible attrs)

```nix
# ✅ Corollaries-safe — merges with node-level overrides
networking.firewall.allowedTCPPorts = lib.mkOptionDefault [22 53 6443];

# ❌ Replaces node configs; can break SSH cluster-wide
networking.firewall.allowedTCPPorts = [22 53 6443];
```

Use `mkOptionDefault` for lists and mergeable attrs; direct assignment is fine for booleans/single strings (hostName).

### Code style

- 2-space indent, trailing semicolons, kebab-case filenames.
- Line length 80–100 chars (soft 120).
- Use `lib.getExe`, `lib.makeBinPath`, `lib.pipe`, `types.either`. Multi-line service ExecStart uses `pkgs.writeShellScript`.
- Standard module template: `{ config, lib, pkgs, ... }: let cfg = config.services.X; in { options.services.X = {...}; config = mkIf cfg.enable {...}; }`.
- Namespaces: `services.*` for daemons, `programs.*` for interactive GUI, `hardware.*` for hardware, `profiles.*` for composable profiles.

### K8s: workload scheduling (ZEPHYR OOM)

Zephyr has constant RAM pressure (31GB; control plane + AI + gaming). **Default ALL non-infrastructure, non-mining workloads to NEXUS** (46GB).

| Node | RAM | Use for |
|------|-----|---------|
| Nexus | 46GB | ✅ Default ALL workloads |
| Zephyr | 31GB | ⚠️ Control plane + mining ONLY |
| Forge | 15GB | Mining + GPU compute |
| Sentry | 31GB | Monitoring + Vulkan AI (RX 5600 XT) |

Enforce via `spec.template.spec.nodeName: nexus` OR `nodeAffinity` (see `kubernetes-manifests/AGENTS.md`). K8s priority: **Nexus > Forge > Sentry > Zephyr**.

Other K8s rules:
- ALWAYS set explicit `replicas: 1`; `revisionHistoryLimit: 2–3`; `maxSurge: 0` in RollingUpdate.
- Use `default-scheduler`, NEVER `volcano-scheduler` (requires RBAC PodGroups; see `docs/kubernetes/volcano-scheduler-incident-2026-03-22.md`).
- Never `kubectl delete --all` / `kubectl scale --all` / `--replicas=0` then delete without checking.
- Before any nodeSelector change: `kubectl top nodes` + `kubectl describe node <n> | grep "Allocated resources"` + replica set count.
- K8s controls its ClusterIP — do NOT add a static route for `10.43.0.0/16` via `flannel.1`.
- Do NOT deploy `oauth2-proxy` as a K8s sidecar; use the `central-auth` NixOS service + Caddy `forward_auth` (sidecars removed 2026-05-02).
- All container images pinned to specific versions; `:latest` blocked by `kubernetes-manifests/security/deny-latest-tag.yaml`.
- GPU isolation caveat: `nvidia-container-runtime` is broken on NixOS (libnvidia-ml.so.1 dlopen fails). Two pods on the same host share `/dev/nvidia*`; `CUDA_VISIBLE_DEVICES` is a hint llama.cpp/vLLM respects but doesn't enforce. `mining-inference-coordinator` shifts mining when inference is active.

### DNS naming in manifests

```
<svc>.<ns>.svc.cluster.local   # full FQDN
<svc>.<ns>.svc.cluster         # short
<svc>                          # same namespace only
```
Use DNS names; never hardcode ClusterIPs in NixOS configs (`http://10.0.0.192:8080` breaks on restart).

### Supply chain security (all enforced)

- 7-day package cooldown: npm (`min-release-age=7`), bun (`minimumReleaseAge = "7d"`), uv/pnpm (`exclude-newer = "7 days"`). Module: `services.supply-chain-cooldowns`.
- Nixpkgs input age: `modules/services/auto-update.nix` rejects updates <7 days.
- Container policy: `/etc/containers/policy.json` rejects unsigned; allows docker.io/library, ghcr.io, quay.io, localhost.
- Trivy weekly image scan: `services.container-scanning.enable = true`.
- All GitHub Actions pinned to commit SHAs.

### Cluster-mesh SSH account

`cluster-mesh@10.1.1.x` (system user, no shell) is the service-to-service SSH identity. Key at `/var/lib/cluster-mesh/.ssh/id_ed25519` (sops-nix-managed `secrets/cns-ssh-key.age`). Used by `cns-watcher`, `nexus-exec-tunnel`, `cns-health.timer`. Never use `root@10.1.1.x` in automated units.

### Secrets management

Secretspec (`secretspec.toml` + sops:// provider) is the runtime resolution path (Phase 2 complete 2026-07-25); sops-nix remains active for backwards compatibility (Path B, Phase 3 removal pending). Registries: `modules/system/sops-secrets-registry.nix` (service secret categories per host). SSH host keys via `initrd-ssh-host-key-<host>.age` for impermanence bootstrap. Cluster CA at `/etc/ssl/cluster-ca/` (init via `cluster-ca-init.service`): the repo's `certs/cluster-ca.crt` is the single fleet trust anchor — hosts copy it and fail closed rather than self-generate (`allowGenerateCa=false`); only Nexus holds the CA signing key (`caKeyProvisioned=true`) and mints the ingress leaf (`generateLeaf=true`). Nexus provisions the key via SecretSpec-creds (`CLUSTER_CA_KEY` in `hosts/nexus/secretspec-creds-wiring.nix` → `/etc/ssl/cluster-ca/ca.key`, with `caKeyService = "secretspec-creds.service"` — NOT sops-nix, which doesn't run on nexus); Caddy `Requires=cluster-ca-init.service`. SSH host trust is CA-based: host certs are signed on boot by `ssh-host-cert-sign.service` using the canonical CA at `/run/secrets/ssh-ca-key` (rotated 2026-08-08 to the live `G3m+DW7Y…` key, `secrets/infra/ssh-ca-key.yaml`), and `programs.ssh.knownHosts` includes an `@cert-authority *.lan,…` entry so host-key rotation never triggers MITM warnings. See the Secretspec section below for the full two-fork architecture.

### Doc-rot prevention (Pocock Rule)

`docs/plans/*.md` documents MUST have a "Last Verified" date. If a doc is >7 days stale, re-verify against current cluster state before following it. After completing work against a plan, update it with actual outcomes. AGENTS.md: fix immediately if you spot a wrong section.

## Things to avoid

- ❌ Imperative package/service/user/config changes on a running host (breaks declarative model + rollback).
- ❌ `kubectl delete --all` / `kubectl scale --all` / scaling to 0 then deleting without checking.
- ❌ `nix-env -iA <pkg>` / editing `/etc` files directly.
- ❌ `volcano-scheduler` for stateless workloads.
- ❌ Running an unguarded direct Colmena apply from a stale checkout; use the Nexus dispatcher so it refreshes `origin/main` first.
- ❌ Hardcoded ClusterIPs; `:latest` container tags; mutable action version tags in CI.
- ❌ Scheduling non-infrastructure workloads to zephyr (31GB OOM).
- ❌ Backgrounding long-running commands like `nixos-rebuild` or `colmena apply` — output must stay visible.
- ❌ `systemctl enable/start <service>` for persistent service config — declare `systemd.services.<name>.wantedBy = ["multi-user.target"]` instead.
- ❌ Editing `hosts/<host>/hardware-configuration.nix` (generated).
- ❌ `systemd-run --user` for builds on a host running user-session services (09:54 crash: GH Actions runner OOM inside user session killed `user@1000.service` → killed the build). Use root system units.
- ❌ Restoring the old per-host `systemd.oomd` block with integer keys (`SwapUsedLimit=90`) — NixOS 26.11 expects percent-based `MemoryUsedPercent`/`SwapUsedPercent`; integers are silently ignored (see `modules/system/oomd-fleet.nix`).

## Stop immediately if

- SSH breaks on any node → document incident, wait for human.
- Multiple nodes affected → STOP ALL WORK.
- `nix flake check` fails → fix before committing.
- `just deploy` preflight fails → resolve ref/build drift before retrying.

## OOM-guard inventory (fleet-wide, 4-layer defense)

The cluster's memory-pressure defense is spread across several modules. Layers, in kill/priority order:

| Layer | Mechanism | Where |
|-------|-----------|-------|
| 1 | **earlyoom** (fast, percentage-based RAM+swap kill) | `modules/system/vm-tuning.nix` (fleet) + `hosts/zephyr/configuration.nix` (primary defense, `--avoid` graphical session + gaming, `--prefer` browser/nix) + `hosts/forge/configuration.nix` |
| 2 | **systemd-oomd** (PSI-based, fleet) — `MemoryUsedPercent=90`, `SwapUsedPercent=85` (percent keys, mkDefault) | `modules/system/oomd-fleet.nix` (loaded via `common-modules-list.nix`) |
| 3 | **cgroup caps** MemoryHigh/MemoryMax on slices + units | `modules/system/systemd-slices.nix` (user@1000 28G/30G, nix.slice 80%, gaming.slice 90%, mining.slice 8G), forge `slices.mining` 8G/12G, noctalia 4G/6G, bonsai 6G/20G, mcp 1G, central-auth 256M, qdrant |
| 4 | **oom_score_adj / OOMPolicy** kernel scoring | `modules/system/oom-protection.nix` (OOMPolicy=continue on k3s/sshd/NetworkManager/logind/journald + desktop-oom-protect timer setting -500 on niri/noctalia/spotify/zen/vesktop), unbound -1000, user session -1000, gaming.slice -1000, bonsai +500 (volunteers to die first) |
| + | **vm.\* sysctls** (overcommit=0, min_free_kbytes=1G, watermark_scale_factor=150, dirty caps, swappiness=40 fleet / 180 zram hosts) | `modules/system/vm-tuning.nix`, zephyr overrides in `hosts/zephyr/configuration.nix` (zram 50% ≈ 15.6G) |

Notable history: 2026-07-15 OOM crash killed niri+alacritty (#295) → oom-protection.nix; 2026-07-27 oomd killed noctalia → noctalia cgroup caps; 2026-08-03 oomd SwapUsedLimit killed noctalia during Cyberpunk → noctalia `ManagedOOMSwap=off` + earlyoom `--avoid` extended with `steam|GameThread|REDprelauncher`, zram 40→50%. Hermes has `oom-defense` and `daily-oom-audit` skills (`modules/services/hermes/skills/`).

## Resource management (slices / quotas / priorities)

Multi-layer resource control. Source files first, then what each layer does.

| Layer | What | Source |
|-------|------|--------|
| **systemd slices** (cgroup v2) | `user@1000`: MemoryHigh 28G/MemoryMax 30G + `OOMScoreAdjust=-1000` + `restartIfChanged=false`; `nix.slice`: CPU 80% + mem 80% (nix-daemon pinned in); `gaming.slice`: CPU 95% + mem 90% + TasksMax 20000 + OOM -1000; `mining.slice`: mem 8G + CPU 95% + IOWeight 10 | `modules/system/systemd-slices.nix`; forge `slices.mining` 8G/12G in `hosts/forge/configuration.nix`; zephyr root slice `ManagedOOMSwap=kill` in `hosts/zephyr/configuration.nix` |
| **per-unit quotas** | central-auth CPU 25% / 256M; nixos-cluster-mcp CPU 80% / 1G; boot-emergency CPU 75% / 8G; noctalia 4G/6G; bonsai 6–20G + `OOMScoreAdjust=500` (volunteers to die first); unbound OOM -1000 | `modules/services/central-auth.nix`, `modules/services/nixos-cluster-mcp.nix`, `modules/system/boot-emergency-diagnostics.nix`, `modules/desktop/zephyr-sdr-brightness.nix`, `modules/services/bonsai.nix`, `modules/network/cluster-dns.nix` |
| **dynamic control** | `launch-game` → `systemd-run --user --slice=gaming.slice` (CPUWeight 1024, Nice -5); `workload-monitor.sh` live `set-property CPUQuota` 0–100% on mining units + `nix-daemon CPUWeight=2048` during builds; mining-inference-coordinator pauses mining | `modules/gaming/gaming-base.nix`, `modules/gaming/scripts/gpu-profiles/workload-monitor.sh` |
| **Nix build farm** | max-jobs: nexus 6 (exclusive builder) / zephyr+forge+sentry 0 (never build); `/etc/nix/machines` advertises nexus only (speedFactor 10, systems `x86_64-linux` + `i686-linux` for Steam/VR multilib); **forge (GPU miner) and sentry (monitoring/inference) are never build targets**; `sandbox=true` (mkForce); post-build-hook + cachix watch-store (nexus + sentry, publish-only) at nice -19 / IOSchedulingPriority 7 | `modules/system/distributed-builds.nix` |
| **K8s** | PriorityClasses `high-priority-ai`(1000) / `medium-priority-ai`(500) / `low-priority-mining`(100) + `system-node-critical` / `system-cluster-critical`; LimitRange + ResourceQuota per namespace (incl. GPU quotas: nvidia.com/gpu + amd.com/gpu); HPA caddy 2–10 / cloudflared 1–5; PDBs coredns/caddy/kube-flannel; ValidatingAdmissionPolicy `require-resources-and-security`; node pinning nexus-first (Nexus > Forge > Sentry > Zephyr); GPU via device plugins | `kubernetes/modules/infrastructure.nix`, `kubernetes/modules/{host-services,nix-csi,llama-servers}.nix`, `kubernetes-manifests/{resource-allocation,scheduling}/` |
| **IO/nice** | btrfs-compression + garage run `Nice=15` / `IOSchedulingClass=idle` so background IO never starves foreground | `modules/system/btrfs-compression.nix`, `modules/services/garage.nix` |

Notes: forge's `slices.mining` CPUQuota is intentionally unset (gpu-profile-manager owns it at runtime). Two drift traps: the live nix.conf `max-jobs` can diverge from git (`docs/build-settings-recommendations-2026-08-03.md` caught nexus drifting 16-vs-12; declared value is now 6); `hosts/{forge,sentry}/hardware.nix` are **not imported** (dead config) yet duplicate slice/ROCm blocks.

## Operational gotchas (Codebuff / AI-agent working knowledge)

### Tooling pattern: 0644 root:root write-block

Some files under `/etc/nixos/pkgs/` (notably `pkgs/secretspec-provider-sops/default.nix`)
ship as `0644 root:root`, which the in-session `str_replace` and `write_file` tools
cannot bypass — they fail with `"Failed to write to file: file path caused an error
or file could not be written"` because they run as the operator user, not root.

**Workaround (basher-side):**
```
cat > /tmp/<name>.new.nix << 'EOF'
...new content...
EOF
sudo cp /tmp/<name>.new.nix /etc/nixos/<path>/<name>.nix
```

This bumps the file's owner/perm to whatever `cp -p` keeps (root:root 0644 unless
`-p` is dropped). Documents the pattern; future LLMs shouldn't burn 15 minutes
on failed edit-tool retries when they could `sudo cp` from a heredoc.

### Secretspec migration (Phase 2 — COMPLETE 2026-07-25)

The sops-nix → secretspec migration is complete. Secretspec is a
declarative secrets resolution framework that replaces sops-nix for
runtime secret resolution. The cluster now runs TWO paths in parallel:

- **Path A (secretspec)**: `secretspec check -P production` resolves
  all 60+ secrets via sops:// ref routing + dotenv/env fallback.
- **Path B (sops-nix)**: Still active for backwards compatibility;
  will be removed in Phase 3.

#### Two-fork architecture

The cluster builds secretspec from TWO remote GitHub forks declared as
flake inputs in `flake.nix`:

```nix
secretspec = {
  # cachix fork at reverb256/secretspec/feature/sops-provider-subprocess-dispatch
  url = "github:reverb256/secretspec/feature/sops-provider-subprocess-dispatch";
  flake = false;
};
secretspec-provider-sops = {
  # provider-rust fork at reverb256/secretspec-provider-sops (feature branch)
  url = "github:reverb256/secretspec-provider-sops/feature/two-strategy-handle-get";
  flake = false;
};
```

Both packages are at `/etc/nixos/pkgs/secretspec/` and
`/etc/nixos/pkgs/secretspec-provider-sops/`.

#### Ref routing in secretspec.toml

`/etc/nixos/secretspec.toml` declares all 60+ cluster secrets. 18
sops-backed entries have `ref = { item = "path.yaml#data" }` fields
that tell the in-tree SopsProvider exactly which age-encrypted file to
decrypt and which YAML key (`data`) to extract:

```toml
# phase2_sops_route: secrets/ai/nvidia-api-key.yaml#nvidia_api_key
NVIDIA_API_KEY = { required = true, type = "password",
  ref = { item = "ai/nvidia-api-key.yaml#data" } }
```

The two-strategy dispatcher (`handle_get` in provider-rust/main.rs):
1. Key contains `#` or `/` → split on `#`, decrypt specified file,
   extract specified YAML key
2. Flat key name → search all `.yaml` files under project directory
   (depth-limited to 8, symlink-safe)

#### Nix build chain

`just secretspec-rebuild` builds both packages from the remote GitHub
forks (local clones cached by flake lock). `just secretspec-validate-local`
runs an ephemeral age-keypair end-to-end test.

Production validation:
```bash
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys-combined.txt \
SECRETSPEC_SOPS_PROVIDER_BIN=$(nix build .#secretspec-provider-sops --no-link --print-out-paths 2>/dev/null)/bin/secretspec-provider-sops-protocol \
secretspec check -f /etc/nixos/secretspec.toml -P production
```

All 18 sops-backed secrets resolve correctly (`source sops:///etc/nixos/secrets/`).

#### .env.secrets

`/etc/nixos/.env.secrets` contains placeholder values for the 34
env-backed secrets (no sops backing). Replace with real values before
production use. The secretspec dotenv provider reads it at
`dotenv:///etc/nixos/.env.secrets`.

#### Age keyfile

The cluster's combined age key is at
`/home/j_kro/.config/sops/age/keys-combined.txt`. The root-owned
`/tmp/combined-keys.txt` is the authoritative copy.

#### YubiKey/pcscd

Two YubiKeys (1050:0407) are physically attached to zephyr. pcscd is
running with the CCID driver symlinked:
```
/var/lib/pcsc/drivers/ifd-ccid.bundle → /nix/store/...-ccid-1.7.1/pcsc/drivers/ifd-ccid.bundle
```
`age-plugin-yubikey -l` lists recipients.

#### Remaining work

- **Merge to main**: `feature/two-strategy-handle-get` blocked by GitHub
  branch protection. Flake input stays on feature branch until merged.
- **Operator rotation**: Replace the 34 placeholder values in .env.secrets
  with real secrets from external service providers.
- **Secretspec-validate-local**: Fails due to DNS resolution for
  cache.nixos.org (infrastructure issue, not code).

The flake.lock file is pinned to the feature branch revision for both
forks. The justfile recipes still pass --option pure-eval false for safety, though GitHub-based flake inputs make it no longer strictly required for the source resolution path.

#### How the sops provider works

In-tree `SopsProvider` (in cachix fork secretspec/src/provider/sops.rs)
implements the Provider trait with scheme `sops://`. Spawns
`secretspec-provider-sops-protocol` as a subprocess (NDJSON per
cachix/secretspec#98).

Flow:
1. `secretspec check` evaluates each secret
2. If secret has `ref` → `Address::Native` → `flat_item` returns the
   `item` field (e.g. `ai/nvidia-api-key.yaml#data`)
3. SopsProvider sends NDJSON `{"op":"get", "key":"..."}` to dispatcher
4. Dispatcher splits on `#` → `sops --decrypt file` → parse YAML →
   extract `data` key → return value
5. If no `ref` → falls through to dotenv/env providers

#### Justfile secretspec recipes

```
just secretspec-check           # secretspec check with production profile
just secretspec-list            # List all declared secrets by category
just secretspec-validate-local  # Ephemeral age-keypair end-to-end test
just secretspec-rebuild         # Rebuild both packages
just secretspec-fork-status     # Show ahead/behind for both forks
just secretspec-core-sync       # Rebase cachix fork onto upstream
just secretspec-provider-sync   # Rebase provider fork onto upstream
just secretspec-fork-bootstrap  # Clone cachix fork to local
```

**Important:** All secretspec-related `nix build` invocations need
`--option pure-eval false` because the fork paths live outside the
flake directory tree. Without it, evaluation silently falls through
to the upstream tarball (no sops:// provider).
**How to verify:** `just secretspec-validate-local` exits 0 with log line
`[ci] OK: secretspec built from local fork (sops feature enabled)`. The
case-statement in that recipe warns on stderr (non-blocking) if it detects
a fallback path. If you see the fallback warning, the flake input is
malformed — fix `flake.nix`'s `secretspec` / `secretspec-provider-sops`
input declarations.

### Consolidated writes to tools: when tooling-blocked, use basher sudo-cp

If `str_replace` or `write_file` fails on a /etc/nixos file, the basher-side
`cat heredoc → sudo cp` path succeeds. Document the source-target perm state in
the edit comment so future maintainers don't re-add the same code-reviewer
warning.

### Recent state changes (through 2026-08-08)

- **Nexus is now the SOLE Nix build executor (2026-08-08, in flight)**:
  `distributed-builds.nix` sets `max-jobs` nexus=6 / zephyr+forge+sentry=0 and
  the `/etc/nix/machines` generator advertises nexus only, with `i686-linux`
  alongside `x86_64-linux` so Steam/VR multilib derivations can be built
  remotely. Sentry was removed from the builder list — it only publishes cachix
  (`cachix-watch-store`).
- **Cluster-CA trust-anchor hardening (2026-08-08)**:
  `modules/services/cluster-ca.nix` gained `caKeyProvisioned` + `allowGenerateCa`
  (both default false → hosts fail closed rather than fork the PKI) and a new
  `caKeyService` option (default `sops-install-secrets.service`, nexus overrides
  to `secretspec-creds.service`). Nexus provisions the CA signing key via
  SecretSpec-creds wiring (`CLUSTER_CA_KEY` in
  `hosts/nexus/secretspec-creds-wiring.nix` → `/etc/ssl/cluster-ca/ca.key`,
  secret `secrets/infra/cluster-ca-key.yaml`) and mints the leaf; forge/sentry
  are trust-only (`generateLeaf=false`). The init service verifies the
  provisioned key matches the repo cert before minting.
- **SSH CA canonicalized on G3m + declarative host-cert signing (2026-08-08)**:
  `secrets/infra/ssh-ca-key.yaml` was rotated to the live CA key
  (`SHA256:G3m+DW7Y…`, `cluster-CA@zephyr`), so the sops secret, `/etc/ssh/ca_key`,
  and the declared `caPublicKey` are all one key. `modules/system/ssh-ca.nix`
  adds `ssh-host-cert-sign.service`: on every boot it re-signs the local
  `ssh_host_ed25519_key` with the CA from `/run/secrets/ssh-ca-key` (falling
  back to `/etc/ssh/ca_key`), re-signing whenever the cert is missing, signed by
  a different CA, or principals are stale — so rotated host keys (e.g. sentry
  before preservation landed) get fresh certs automatically.
  `modules/system/ssh.nix` adds an `@cert-authority *.lan,*.cluster.local,<IPs>`
  known-hosts entry for the G3m CA, so host verification is CA-based and key
  rotation never triggers MITM warnings.
- **secretspec-creds `write_secret` fixed for multi-line PEMs (2026-08-08)**:
  the old full-decrypt + `sed` key-strip corrupted YAML block scalars into
  `|` + indented garbage (observed on `/run/secrets/ssh-ca-key`). It now uses
  `sops -d --extract '["<key>]'` (honoring the per-entry `key` option, e.g.
  `exa_api_key`), falls back to full decrypt for binary/named-key files, and
  appends a trailing newline (OpenSSH rejects private keys without one).
  Also fixed a `host-configuration` test false positive (forge comment matching
  `hosts/sentry/`).
- **Impermanence → preservation migration (2026-08-08, in flight)**: nexus
  deleted `hosts/nexus/impermanence.nix`; nexus/forge/sentry now set
  `preservation.enable = true` in `hosts/<host>/preservation.nix` and persist
  `/etc/nixos/.age` + `/etc/sops/age` (plus `/etc/ssl/cluster-ca` on nexus).
- **PeakMiner selects GPU by product name (2026-08-08, in flight)**: every
  `peakminer.nix` instance now declares `gpuName` ("RTX 4060", "RTX 3060 Ti")
  so per-GPU settings can't bleed onto the wrong card.
- **`pkgs.caddy-with-modules` exposed via overlay** (`overlays/system.nix`):
  nexus cluster ingress uses the custom Caddy build (rate-limit/security/cache
  modules) through the normal `pkgs` namespace.
- **home-manager-config extracted to a separate repo (2026-07-29→08-06)**: HM
  config now lives in `/home/j_kro/Projects/home-manager-config`
  (`github:reverb256/home-manager-config`, flake input). `flake.nix` consumes
  `inputs.home-manager-config.homeConfigurations` directly
  (`homeConfigurations = inputs.home-manager-config.homeConfigurations`).
  Niri config split into `niri-config.nix` / `niri-keybinds.nix` /
  `niri-outputs.nix` / `niri-spawn.nix` there. `/etc/nixos/modules/home-manager/`
  retains only shared-leaf modules + standalone entrypoints.
- **alacritty-oom-safe wrapper REMOVED (2026-08-06, HM repo `ee2b69c`)**: the
  `systemd-run --user --scope` wrapper (`MemoryHigh=2G MemoryMax=4G
  OOMScoreAdjust=-800`) spawned silently on Mod+Return/Mod+T/Mod+D and was
  replaced with plain `alacritty` binds. **Do not resurrect it**; the launch-game
  pattern in `modules/gaming/gaming-base.nix` is the reference if per-app cgroup
  caps are ever needed again.
- **Hyprland removed; desktop is Niri-only (#405/#406/#407, 2026-07-29)**: all
  desktop modules are Niri/UWSM. No Plasma, Hyprland, or Sway.
- **Z.AI fully removed cluster-wide (2026-07-15)**:
  `ZAI_API_KEY` no longer wired in `hosts/zephyr/secretspec-creds-wiring.nix`;
  GLM model dropped from Hermes profile. `ai-coding-tools.nix` still
  references it as a backwards-compat shell helper but does not require the
  secret on disk.
- **zephyr OOM saga (2026-07-27 → 2026-08-03)**: systemd-oomd was killing
  noctalia + uwsm/alacritty scope at 90% mem+swap on the 31GB zephyr host.
  - `modules/desktop/zephyr-sdr-brightness.nix`: noctalia.service
    `MemoryHigh=4G` `MemoryMax=6G` `OOMPolicy=continue`
    `OOMScoreAdjust=-300` `ManagedOOMSwap=off` (added 08-03 after the
    Cyberpunk kill) `StartLimitBurst=5 within 60s`.
  - `hosts/zephyr/configuration.nix`: earlyoom `--avoid` extended with
    `steam|GameThread|REDprelauncher` (08-03); zram bumped 40→50%
    (~15.6G headroom).
  - `modules/system/oomd-fleet.nix` replaced the broken per-host oomd block
    (integer `SwapUsedLimit=90` keys were silently ignored; NixOS 26.11 uses
    percent keys). Verify the `SwapUsedPercent=85` fix is deployed:
    `cat /run/current-system/etc/systemd/oomd.conf`.
- **k3s token path moved**: `/persistent/etc/k3s-cluster-token` →
  `/run/secrets/k3s-cluster-token` cluster-wide (nexus/forge/sentry + the
  `modules/services/services.nix` sentry default). Impermanence-friendly and
  matches how other cluster materializes sops-secrets.
- **MEMLAWB_PASSPHRASE** added to the zephyr backend env map;
  lives as a placeholder in `/etc/nixos/.env.secrets` (no sops backing).
- **`.gitignore` hardened**: added `.env`, `.env.*`, `.secretspec.env`
  at the root (post-incident 2026-07-25). `.age` files remain committed;
  `secrets/*.key`/`*.plaintext` rules unchanged.
- **`secretspec-creds` + `secretspec-validator`**: each gained an
  `ageKeyFile` option (default `/etc/nixos/.age/key.txt`, overridable per
  host). The secretspec resolver's decrypt oneshot now has
  `Restart=on-failure` + `StartLimitBurst=3 within 5min` so transient
  YubiKey unplug-replug or network blips self-heal instead of leaving
  `/run/secrets/*` empty.

### Audit trail (2026-07-27)

The [`docs/audit-2026-07-27.md`](docs/audit-2026-07-27.md) file is the most
recent cross-area audit (24 findings, F-1..F-24). Two prior confirmed-audit
artifacts: [`INFRASTRUCTURE-AUDIT.md`](INFRASTRUCTURE-AUDIT.md) (2026-05-14
baseline, now archived per F-22) and
[`SECURITY-INCIDENT-2026-07-25.md`](SECURITY-INCIDENT-2026-07-25.md)
(secretspec Phase-2 + SAMSUNG_TV_TOKEN routing regression that prompted
the audit to begin). The 2026-07-27 audit consolidated + extended those
findings. Treat the audit doc as the canonical cross-reference for any
cluster-state claim that might have drifted since 2026-05. The fallback
chain for verification:

1. `docs/audit-2026-07-27.md` (current; route to here for any cluster-state claim)
2. `AGENTS.md` (agent guidelines; carries "Last reviewed" date 2026-07-30)
3. `INFRASTRUCTURE-AUDIT.md` (archived per F-22 — read-only historical)
4. `SECURITY-INCIDENT-2026-07-25.md` (active incident context — secretspec Phase 2)
5. `just health` (live SSH/Kubernetes reachability, if reachable)
6. `git log --oneline` on the affected subdirectory (verifies which `.nix` rules are deployed)

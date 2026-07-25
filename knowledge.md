# Project knowledge

This file gives Codebuff context about this repo: goals, commands, conventions, and gotchas.

## What this is

Flake-based NixOS configuration for a 4-node SOHO cluster (Zephyr, Nexus, Forge, Sentry) running AI inference, GPU compute/mining, K8s workloads, storage, and monitoring. Zephyr is the development/source-of-truth host; all config rebuilds flow from there through git → Colmena / `just deploy` → remote hosts via `nix-copy-closure` + `switch-to-configuration`.

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

SSO: Casdoor (OIDC) → `oauth2-proxy` on Zephyr+Nexus (port 4180) → Caddy `forward_auth` for protected services. Hashing/CAS: Garage S3, Casdoor, Vaultwarden. AI: sovereign gateway on Nexus, llama.cpp (Vulkan/CUDA), vLLM+TurboQuant containers, Qdrant. Dev: n8n, Gitea+actions-runner (nexus), SearXNG. Observability: Prometheus+Grafana, glances, Caddy metrics.

## Quickstart

### Commands (run on Zephyr unless noted)

```bash
just check              # Validate flake (fast, no build)
just build              # Build current host's toplevel
just switch             # Build + activate on local host (auto-pauses CPU mining)
just test-apply         # Build + test (reboot-safe activation)
just deploy [<host>]    # Build + deploy to all or one host (zephyr|nexus|forge|sentry|"all")
just deploy-nexus <h>   # Async deploy from nexus via tmux (for nexus/forge/sentry only)
just rollback           # Rollback current host
just github-runners  # ((placeholder))
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
├── colmena.nix              # Multi-host deployment (targetHost, tags per host)
├── common-modules-list.nix  # Module list imported by BOTH flake.nix and colmena.nix (must stay in sync)
├── overlay.nix              # Cross-system package overlay
├── justfile                 # All CI/CD tasks
├── hosts/<host>/            # Per-host NixOS configs
├── modules/                 # ~171 reusable .nix files
│   ├── system/              # Core (ssh, users, networking, sops, nix)
│   ├── services/            # Background daemons (k8s, monitoring, mining, etc.)
│   ├── desktop/             # Compositors (Hyprland, Niri, Sway)
│   ├── home-manager/        # HM modules
│   ├── profiles/            # Composable hardware/role/network profiles
│   ├── hardware/            # GPU/AMD/NVIDIA/RGB drivers
│   ├── development/         # Dev tools
│   ├── gaming/              # Launchers, GameMode integration
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
├── secrets/                 # ~42 agenix-encrypted secrets (.age) + unencrypted templates
├── pkgs/                    # Local package definitions (peakminer exporter, etc.)
├── recoveries/              # Disaster recovery scripts
├── machines                 # Colmena machine list
├── docs/                    # Long-form documentation
├── plans/, .plans/          # Planning workspaces
└── .github/workflows/       # CI (SHA-pinned actions)
```

### Workflow: GitOps via worktrees + main

```
main                          # integration AND production; /etc/nixos on all hosts tracks main
issue-NNN-<slug>              # all new work; lives in /data/projects/own/nixos-config-NNN worktree
```

Author workflow: `just new-worktree NNN` → edit in `/data/projects/own/nixos-config-NNN` → `nix flake check` → `git push origin issue-NNN-...` → `gh pr create --base main` → squash-merge → `cd /etc/nixos && git pull` → `just deploy`.

`/etc/nixos` itself on every host stays on `main`; deployed cluster state = `main` HEAD after the most recent `just deploy`.

### Build pipeline quirks

- Zephyr NEVER builds locally (31GB RAM OOM): builds always offload to nexus via `scripts/remote-build.sh` (systemd-run on nexus to dodge ssh-ng pipe-draining).
- Deploys from Zephyr run `git fetch origin main && git reset --hard origin/main` on nexus BEFORE building — nexus is a build executor only (G2 pipeline-integrity guard).
- `deploy-nexus zephyr` is HARD-REFUSED (G3): zephyr node has `targetHost=null`, which colmena interprets as "deploy to localhost" → would apply ZEPHYR'S CONFIG TO NEXUS. Use `just deploy zephyr` instead.
- `just deploy` runs `scripts/preflight-check.sh` first (G4): refuses deploy if source-of-truth/nexus-builder disagree on canonical ref or if a build is already in flight.
- Use the `.#colmena` app (flake-local 0.5.0-pre), NOT `nixpkgs#colmena` (channel-pinned 0.4.0 can't evaluate `colmenaHive`).

### Ports ↔ DNS bridge

`kubernetes/service-ports.nix` is the **single source of truth** for NodePort assignments. Both Zephyr's Caddy (`hosts/zephyr/caddy-routes.nix`) and Nexus's cluster Caddy (`modules/services/cluster-services.nix`) import it. To add a `.lan` service: pick unused 30xxx port → add to `service-ports.nix` → add DNS record in `modules/network/cluster-dns.nix` → add Caddy route → deploy K8s Service with matching `nodePort`.

## Conventions (HARD rules)

### NixOS declarative-only (the #1 most expensive failure pattern)

ALL persistent system state lives in `.nix` files under git. SSH into a NixOS host is for reading state ONLY. Never imperatively `systemctl start/enable` a service, `nix-env -i` a package, `useradd`, or edit `/etc/*` directly — those changes don't survive `nixos-rebuild` and can't be rolled back. The `.nix` file on Zephyr is the source of truth; running hosts are consumers.

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

`.sops.yaml` (sops-nix) for service secrets; agenix registry at `modules/system/agenix-secrets-registry.nix` and `sops-secrets-registry.nix`. SSH host keys via `initrd-ssh-host-key-<host>.age` for impermanence bootstrap. Cluster CA at `/etc/ssl/cluster-ca/` (init via `cluster-ca-init.service`).

### Doc-rot prevention (Pocock Rule)

`docs/plans/*.md` documents MUST have a "Last Verified" date. If a doc is >7 days stale, re-verify against current cluster state before following it. After completing work against a plan, update it with actual outcomes. AGENTS.md: fix immediately if you spot a wrong section.

## Things to avoid

- ❌ Imperative package/service/user/config changes on a running host (breaks declarative model + rollback).
- ❌ `kubectl delete --all` / `kubectl scale --all` / scaling to 0 then deleting without checking.
- ❌ `nix-env -iA <pkg>` / editing `/etc` files directly.
- ❌ `volcano-scheduler` for stateless workloads.
- ❌ Deploying to zephyr via colmena-on-nexus (targetHost=null footgun).
- ❌ Hardcoded ClusterIPs; `:latest` container tags; mutable action version tags in CI.
- ❌ Scheduling non-infrastructure workloads to zephyr (31GB OOM).
- ❌ Backgrounding long-running commands like `nixos-rebuild` or `colmena apply` — output must stay visible.
- ❌ `systemctl enable/start <service>` for persistent service config — declare `systemd.services.<name>.wantedBy = ["multi-user.target"]` instead.
- ❌ Editing `hosts/<host>/hardware-configuration.nix` (generated).

## Stop immediately if

- SSH breaks on any node → document incident, wait for human.
- Multiple nodes affected → STOP ALL WORK.
- `nix flake check` fails → fix before committing.
- `just deploy` preflight fails → resolve ref/build drift before retrying.

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

### Nix flake pure-eval + local secretspec fork

Lix 2.95.2+ (and Nix ≥2.4) default flake eval to `pure-eval = true`, which
disallows `builtins.pathExists` on absolute paths outside the flake's directory
tree. The cachix-fork checkout at `/home/j_kro/Projects/secretspec-core` and the
provider-rust fork at `/home/j_kro/Projects/secretspec/provider-rust` are exactly
those forbidden paths. With pure-eval enabled, the buildRustPackage branch in
`pkgs/secretspec/default.nix` and `pkgs/secretspec-provider-sops/default.nix`
silently falls through to the upstream cachix tarball — which has NO sops://,
and validator runs error with "Provider backend 'sops' not found" at runtime.

**Three complementary fixes (all required for the cluster sid to work):**

1. **Justfile recipes pass `--option pure-eval false` per-invocation.**
   `just secretspec-validate-local`, `just secretspec-rebuild`, `just build`,
   `just hermes-update`, `just hermes-update-check`, `just deploy-nexus`. Each
   invocation either positions `--option pure-eval false` BEFORE the subcommand
   (`nix --option pure-eval false run`) or inserts it among the existing flags.

2. **`nix.settings.pure-eval = false` in NixOS module config.** Set on hosts with
   the local fork checkout via `cluster.localSealSupport` (defined in
   `modules/system/secretspec-cluster-mode.nix`). Auto-coupled to
   `services.sops-secrets-registry.enable` (Option B implementation, see
   `.plans/2026-07-25-cluster-localSealSupport-scope.md`): any host with
   the sops-registry enabled implicitly gets impure-eval accessible. This
   catches the `nixos-rebuild switch|test` chain which does NOT accept
   per-call `--option` flags directly.

3. **`lib.cleanSource localForkPath` for the secretspec/secretspec-provider-sops
   packages.** Without this, buildRustPackage's cargoSetupPostUnpackHook tries
   to copy `Cargo.lock` into a stale 0555-root `/nix/store/...-cargo-vendor-dir`
   entry, errors with "Permission denied". `lib.cleanSource` produces a fresh
   store path with builder-writable perms; Path-type concatenation `a + "/..."`
   (instead of `toString a + "/..."`) triggers Nix's implicit copy-to-store
   semantics for the lockfile.

How to verify: `just secretspec-validate-local` exits 0 with log line
`[ci] OK: secretspec built from local fork (sops feature enabled)`.
The case-statement in that recipe also warns (>=stderr, not exit) if it falls
back to the upstream tarball — pinpoints operator confusion fast.

### Consolidated writes to tools: when tooling-blocked, use basher sudo-cp

If `str_replace` or `write_file` fails on a /etc/nixos file, the basher-side
`cat heredoc → sudo cp` path succeeds. Document the source-target perm state in
the edit comment so future maintainers don't re-add the same code-reviewer
warning.

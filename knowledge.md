# Project knowledge — nixos-config

> **Last verified:** 2026-08-16 (repo HEAD). Re-verify any dated claim older than ~7 days before acting on it.

Freebuff's distilled index for this repo. The canonical agent guidance is
[`AGENTS.md`](AGENTS.md); task procedures are in `agents/skills/`; deep reference
is in `docs/reference/` and `docs/current-state.md`.

## What this is

Flake-based NixOS config for a 4-host SOHO cluster — Zephyr (10.1.1.110),
Nexus (10.1.1.120), Forge (10.1.1.130), Sentry (10.1.1.140) — running AI
inference, GPU compute/mining, K8s, storage, and monitoring. Zephyr is the
source-of-truth host; deploys flow git → Nexus (sole builder) → colmena → hosts.

Three layers: 1 = NixOS (this repo), 2 = Home Manager
(`github:reverb256/home-manager-config`, a separate repo), 3 = `nix profile`
high-churn binaries.

## Commands

```bash
just check              # validate flake (fast, no build)
just build              # build local host toplevel
just switch             # build + activate local host
just test-apply         # build + test activation without a permanent switch
just deploy [<host>]    # build + deploy to all or one host (preflight-gated)
just rollback           # roll back current host
just status             # git branch/commit/worktree state
just health             # SSH reachability + kubectl get nodes
just new-worktree NNN   # create worktree for issue NNN
just full-check         # scripts/check.sh (lint + security + parse)
just hm-switch          # activate Layer-2 home-manager (no NixOS rebuild)
```

## Documentation layout

| Path | Content |
|------|---------|
| `AGENTS.md` | universal rules, style, conventions — start here |
| `agents/skills/` | task procedures (deploy, add-service, k8s, secrets, worktrees, docs, OOM) |
| `docs/reference/` | architecture, services/auth, MCP, known issues |
| `docs/current-state.md` | authority boundaries + current architecture |
| `docs/DECISION_LOG.md` | decision records |
| `DOCUMENTATION_INDEX.md` | full documentation catalog |

## Top gotchas

- **Declarative only** — edit `.nix` and deploy with `just deploy`; never
  `systemctl enable/start` a persistent service, `nix-env -i`, or edit `/etc`
  directly on a host. The live host is a rolled-back snapshot, never authoritative.
- **`mkOptionDefault`** for lists/mergeable attrs in shared modules — direct
  assignment replaces node configs and can break SSH cluster-wide.
- **Zephyr OOM** — default non-infra/non-mining K8s workloads to Nexus (46GB);
  Zephyr (31GB) is infra + mining only. See `agents/skills/oom-safety.md`.
- **Nexus is the sole builder** — zephyr/forge/sentry run `max-jobs=0`.
- **Secrets** — SecretSpec (`secretspec.toml`) is the runtime schema; sops-nix is
  the compat path. Verify with `just secretspec-check`.
- **CI trust boundary** — PR workflows are read-only and secret-free; deploy is
  `workflow_dispatch` on `main` behind the `homelab-production` environment.

## Freebuff tooling note

Some files under `pkgs/` (notably `pkgs/secretspec-provider-sops/default.nix`)
ship as `0644 root:root`, which `str_replace`/`write_file` cannot overwrite
because they run as the operator user. Fallback:

```bash
cat > /tmp/<name>.new.nix << 'EOF'
...new content...
EOF
sudo cp /tmp/<name>.new.nix <repo>/pkgs/<name>/default.nix
```

## Where key code lives

- Hosts: `hosts/<host>/` bodies + `modules/hosts/<host>/default.nix` (dendritic wiring).
- Shared modules: `modules/` (system, services, desktop, home-manager, profiles, hardware, gaming, network, security).
- K8s: `kubernetes/` (easykubenix) + `kubernetes-manifests/`; NodePorts are in `kubernetes/service-ports.nix`.
- Deploy: `justfile` + `scripts/deploy/` + `.github/workflows/deploy.yml`.

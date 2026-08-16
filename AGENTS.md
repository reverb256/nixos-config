# NixOS Cluster — Agent Guidelines

> **Last reviewed:** 2026-08-16 · Source branch: `main` · Verify live state with `just health`.

Flake-based NixOS configuration for a 4-host cluster (Zephyr, Nexus, Forge,
Sentry). This file holds the universal rules, style, and conventions. Task
procedures live in `agents/skills/`; deep reference lives in `docs/reference/`
and `docs/current-state.md`. Read the matching guide before starting work.

## 🔴 HARD RULE: declarative only — never imperative

**All persistent NixOS state lives in `.nix` files under git.** Shell commands on
a running host are only acceptable for reading state. They are never acceptable
for configuring services, fixing bugs, attaching devices, changing networking,
editing secrets, or patching running daemons.

The workflow for any NixOS change:

1. Edit the `.nix` file on Zephyr (the source-of-truth host, normally in an issue worktree).
2. Validate with `just check` and the relevant build/test recipe.
3. Merge the reviewed change to `main`.
4. Deploy with `just deploy [<host>]`.

The live host is a *consumer* of the config, never the source of truth. A running
host is a rolled-back snapshot.

**This rule is the #1 most expensive recurring failure pattern.** If your first
instinct is to SSH into a host and run a command, stop — find the `.nix` file.

## Quick start

```bash
just check              # quick flake validation (no build)
just build              # build the current host toplevel
just switch             # apply to the local host
just test-apply         # build + test activation without a permanent switch
just deploy [<host>]    # build + deploy to all or one host
just rollback           # roll back the current host
just status             # git branch/commit/worktree state
just health             # SSH reachability + kubectl get nodes
just new-worktree <NNN> # create a worktree for issue NNN
```

> `just test` does not exist. Use `just test-apply`, `just check`, or `just full-check`.

## Configuration layers

| Layer | Where | Owns |
|-------|-------|------|
| 1 — NixOS | this repo (`reverb256/nixos-config`) | hosts, services, networking, hardware, deployment |
| 2 — Home Manager | `github:reverb256/home-manager-config` (flake input) | user config, niri settings/keybinds, app configs |
| 3 — nix profile | `nix profile` | high-churn binaries (Hermes, Freebuff) — never collide with Layer 2 |

`just hm-switch` activates the current host's standalone HM output;
`just hm-build <host>` dry-builds it.

## Safety rules

### `mkOptionDefault` for extensible options (mandatory)

```nix
# ❌ replaces node configs — can break SSH cluster-wide
networking.firewall.allowedTCPPorts = [22 53 6443];

# ✅ merges with node-level overrides
networking.firewall.allowedTCPPorts = lib.mkOptionDefault [22 53 6443];
```

Use `mkOptionDefault` for lists and mergeable attrs. Direct assignment is fine
for booleans and single strings (`hostName`).

### Workload scheduling — Zephyr OOM prevention

Zephyr has 31GB and constant RAM pressure. Default **all** non-infrastructure,
non-mining workloads to Nexus (46GB). Priority: **Nexus > Forge > Sentry > Zephyr**.
See `agents/skills/add-k8s-workload.md`.

### GPU isolation limitation

`nvidia-container-runtime` is broken on NixOS (libnvidia-ml.so.1 dlopen fails).
`CUDA_VISIBLE_DEVICES` is a hint, not isolation. Use
`mining-inference-coordinator` to shift mining while inference runs.

### Stop immediately if

- SSH breaks on any node.
- Multiple nodes are affected.
- `nix flake check` fails.
- `just deploy` preflight fails.

## Code style

- 2-space indent, trailing semicolons, kebab-case filenames.
- Line length 80–100 chars (soft 120).
- `lib.getExe` for `ExecStart`; `pkgs.writeShellScript` for multi-line scripts;
  `lib.makeBinPath` for PATH; `lib.pipe` for transforms; `types.either` for
  flexible options.
- Module template and namespaces: see `agents/skills/add-service.md`.

| Namespace | Usage |
|-----------|-------|
| `services.*` | background daemons |
| `programs.*` | interactive GUI apps |
| `hardware.*` | hardware config |
| `profiles.*` | composable profiles |

## Supply chain

- 7-day package cooldown (npm, bun, uv/pnpm); nixpkgs input age gate.
- No `:latest` container tags (admission policy enforces).
- GitHub Actions pinned to full commit SHAs.

## Task guides (`agents/skills/`)

| Guide | When |
|-------|------|
| `deploy.md` | running `just deploy` / rollback / activation |
| `add-service.md` | adding a NixOS service or `.lan` route |
| `add-k8s-workload.md` | adding or moving a Kubernetes workload |
| `secrets.md` | secretspec / sops-nix secret wiring |
| `worktree-and-pr.md` | issue → worktree → PR → merge → deploy |
| `docs-maintenance.md` | doc freshness (Pocock Rule) |
| `oom-safety.md` | memory limits and OOM defense |

## Reference

| Document | Purpose |
|----------|---------|
| `docs/current-state.md` | checked-in architecture and authority boundaries |
| `docs/reference/cluster-architecture.md` | host wiring, layout, build architecture, CI runner |
| `docs/reference/services-and-auth.md` | SSO/OIDC, service bridge, Caddy/DNS, cluster-mesh, DE VM |
| `docs/reference/mcp-and-agents.md` | MCP servers, model endpoints, agent principles |
| `docs/reference/known-issues.md` | hardening, incidents, deployment lessons |
| `docs/DECISION_LOG.md` | architectural decisions and rationale |
| `DOCUMENTATION_INDEX.md` | full documentation catalog |
| `docs/HARDWARE.md` | checked-in hardware inventory |

## Workflow

`main` is integration **and** production. All work goes through
issue → worktree → PR → squash-merge → `just deploy`. Full procedure in
`agents/skills/worktree-and-pr.md`.

## Writing style

User-facing prose follows ASD-STE100 plus Zinsser: imperative mood, one idea per
sentence, plain words, conclusion first. "Use, do, run, make, check, show" — not
"utilize, execute, perform, demonstrate." When unsure, say so; never fabricate.

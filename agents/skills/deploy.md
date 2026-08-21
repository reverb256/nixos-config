# Deploying the cluster

**Last verified:** 2026-08-21 (deploy-rs migration)

Use this before any `just deploy`, `just rollback`, or host activation.

## Golden rules

- The `.nix` files on Zephyr are the source of truth. Running hosts are consumers,
  never authoritative.
- Deploy from a clean `main` checkout. Never apply from a stale or dirty tree.
- Never background a deploy command. Output must stay visible.
- `just deploy` runs preflight, which refuses source/builder drift, failed
  self-healing, a stale `origin/main`, or an in-flight build.

## Flow

```bash
just check              # quick flake validation (no build)
just deploy-rs-check    # validate deploy-rs profiles (deployChecks)
just deploy [<host>]    # build + deploy to all or one host via deploy-rs
just rollback           # roll back the current host
```

## Deployment executor: deploy-rs (2026-08-21)

`just deploy` routes through the Nexus dispatcher (`nexus-dispatch.sh`), which
builds the closure on Nexus and activates it with **deploy-rs** (serokell) —
the replacement for colmena as the deployment layer.

deploy-rs provides natively what colmena lacked:

- **autoRollback**: if activation fails, the previous generation is re-activated.
- **magicRollback**: a target-side inotify watcher reverts the node if the
  deployer cannot confirm it is reachable within `confirmTimeout` (120s).
  This survives reboots and network changes — a bad kernel/network change
  cannot brick a host silently.
- **deployChecks**: `deploy-schema` + `deploy-activate` validate the deploy
  output during `nix flake check` / `just check`.

Nodes are derived from `contracts/host-inventory.nix` (the same typed inventory
colmena read). The NixOS activator runs `switch-to-configuration` — the same
activation path colmena used, so secretspec-creds / sops-nix activation scripts
are unchanged.

## Targets

`just deploy zephyr|nexus|forge|sentry|all`

`just deploy-nexus <host>` runs the deploy asynchronously from Nexus via tmux
(for nexus/forge/sentry only). Inspect it with `just deploy-nexus-{attach,logs,stop}`.

Direct invocations (after the dispatcher):

```bash
nix run .#apps.x86_64-linux.deploy-rs -- .#nexus        # single host
nix run .#apps.x86_64-linux.deploy-rs -- .#all          # all hosts
```

## Gotchas

- Nexus is the sole build executor; Zephyr, Forge, and Sentry never build
  locally — they dispatch to Nexus.
- `colmena` remains as the *evaluation* layer (`colmena.nix` still produces the
  hive for validation), but **deployment is deploy-rs**. Do not use `colmena
  apply` for deploys.
- A direct, unguarded deploy from a stale checkout is forbidden. The
  dispatcher refreshes `origin/main` first.
- A failed deploy automatically triggers deploy-rs's autoRollback/magicRollback.

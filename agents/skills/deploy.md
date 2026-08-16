# Deploying the cluster

**Last verified:** 2026-08-16

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
just test-apply         # optional: build + test activation without a permanent switch
just deploy [<host>]    # build + deploy to all or one host
just rollback           # roll back the current host
```

## Targets

`just deploy zephyr|nexus|forge|sentry|all`

`just deploy-nexus <host>` runs the deploy asynchronously from Nexus via tmux
(for nexus/forge/sentry only). Inspect it with `just deploy-nexus-{attach,logs,stop}`.

## Gotchas

- Nexus is the sole build executor (`max-jobs=6`); Zephyr, Forge, and Sentry never
  build locally — they dispatch to Nexus.
- Use the flake-local `.#colmena` app, never `nixpkgs#colmena` (it cannot evaluate
  `colmenaHive`).
- A direct, unguarded `colmena apply` from a stale checkout is forbidden. The
  dispatcher refreshes `origin/main` first.
- A failed deploy automatically attempts `colmena rollback`.

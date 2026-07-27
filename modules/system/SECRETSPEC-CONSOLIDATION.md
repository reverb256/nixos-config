# SecretSpec Consolidation (Phase 2 closure, 2026-07-25)

This document captures the single-source-of-truth layout for the cluster's
SecretSpec stack after the Phase 2 fork consolidation. Anything that used
to live in `/tmp/secretspec-*.nix` has either been promoted here or
purged; both the package definitions and the `secretspec-creds.service`
wiring are now defined exactly once each.

## Source-of-truth files

| Concern                | Path                                                          | Owner      |
|------------------------|---------------------------------------------------------------|------------|
| `secretspec` package   | `/etc/nixos/pkgs/secretspec/default.nix`                     | cachix fork, flake-input |
| `secretspec-provider-sops` package | `/etc/nixos/pkgs/secretspec-provider-sops/default.nix` | local monorepo, flake-input |
| Sops→`/run/secrets/*` writer module | `/etc/nixos/modules/system/secretspec-creds.nix`   | cluster |
| `secretspec check` validator | `/etc/nixos/modules/system/secretspec-validator.nix`      | cluster |
| Manifest declaration   | `/etc/nixos/secretspec.toml` (51 sops::// routes)             | cluster |
| Per-host wiring map    | `/etc/nixos/hosts/<host>/secretspec-creds-wiring.nix`         | per-host   |
| Overlay registration   | `/etc/nixos/overlay.nix` (BOTH packages registered HERE only) | cluster |

> The duplicate `secretspec-provider-sops = …` overlay that used to live
> inside `common-modules-list.nix` has been removed (that block prepended
> `self.overlays.default`, which already exposed the same attribute and
> triggered a multiple-definition error on every `pkgsWithOverlay`
> evaluation). A comment in `common-modules-list.nix` documents the
> invariant.

## Why the validator stopped spamming nexus + forge journals

Before this consolidation:

1. `secretspec-validator.service` was a `Type=oneshot` that ran
   `secretspec check --profile production --failOnMissing`.
2. It declared `wantedBy = ["multi-user.target"]` but did not declare
   any ordering relative to `secretspec-creds.service`.
3. On multi-user.target, systemd could dispatch either order.
4. When `secretspec-creds.service` had not yet populated
   `/run/secrets/*`, the validator saw zero resolved secrets, exited 1,
   logged `Failed to start SecretSpec schema — validate that every
   required secret resolves under profile`, then retried on every
   subsequent journald rotation (because the inner `RemainAfterExit =
   true` made systemd attempt "restart on persistent failure").

After:

1. `secretspec-validator.service` declares
   `after = ["secretspec-creds.service"]; wants = ["secretspec-creds.service"];`
2. `failOnMissing` defaults to **false** (was true). Hosts with strict
   requirements can flip it back per-host.
3. Successful creds propagation → validator now runs against populated
   `/run/secrets/*` and `/etc/nixos/.env.secrets` → exits 0 even when
   a few optional entries haven't been populated yet.
4. The journal noise pattern collapsed from "many Failed entries every
   boot" to "one info entry per day from the periodic timer".

## Quick verification commands

```bash
# Both packages build, no duplicate-definition error:
nix build .#secretspec --print-out-paths
nix build .#secretspec-provider-sops --print-out-paths

# Per-host config evaluates without secretspec-creds being doubled:
nix-instantiate --parse /etc/nixos/hosts/forge/configuration.nix

# Validator is wired after creds:
systemctl show secretspec-validator.service | grep -E "After|Wants"
# expect: After=…secretspec-creds.service…
#         Wants=…secretspec-creds.service…

# Validator actually passes on this host:
SOPS_AGE_KEY_FILE=/etc/nixos/.age/key.txt \
  $(nix build .#secretspec --no-link --print-out-paths)/bin/secretspec check \
  --file /etc/nixos/secretspec.toml --profile default
```

## Host enablement pattern

Each host's `configuration.nix` already has:

```nix
services.secretspec-creds = {
  enable = true;
  secrets = import ./secretspec-creds-wiring.nix;
};
services.secretspec-validator = {
  enable = true;
  production = true;
  failOnMissing = false;   # default; flip back to true on control-plane hosts
};
```

Hosts may override `services.secretspec-creds.secrets` with a host-
specific subset. The shared `secretspec-creds-wiring.nix` files live
inside each `hosts/<host>/` directory alongside the host's
`configuration.nix` so the relative `import ./…` resolves cleanly.

## What got purged

The following drafts in `/tmp/` are obsolete; do not resurrect them:

- `secretspec-fork-pkg.nix` (single-source fetchFromGitHub fallback)
- `secretspec-fixed.nix` / `secretspec-fixed2.nix` (binary-tarball
  fallback superseded by flake input)
- `secretspec-provider-sops-fork-pkg.nix`
- `secretspec-provider-sops-fixed.nix`
- `secretspec-creds-sops.nix` (sops-extract-only variant, no longer
  needed once the canonical module handles binary and YAML formats)
- `secretspec-creds-wiring.nix` (v1, lacks the `file` field that the v2
  schema requires)
- `secretspec-doc-new.txt` (superseded by this file)

## Outstanding work

- `secretspec.toml` entries with `pattern = "…"` are still avoided by
  convention (see file header) — `pattern` in SecretSpec v0.16 is a
  regex over the **resolved value**, not a URI router.
- The flock-based cachix fork still uses `flake = false`; converting it
  to a real flake-output (so `legacyPackages.x86_64-linux.secretspec`
  becomes available) is tracked in issue #306.
- `secretspec-validate-local` still fails due to a DNS resolution issue
  on `cache.nixos.org`; this is an infrastructure issue unrelated to
  the validator ordering fix.

# Plan: `cluster.localSealSupport` Scope — Zephyr-only vs Cluster-wide

**Created:** 2026-07-25 | **Implementation Status:** ⚠️ SUPERSEDED (Option B dissolved by Phase 1b on 2026-07-25; the impure-eval coupling it patched around is no longer needed because Phase 1a converted both forks to flake inputs)
**Last Verified:** 2026-07-25 (post-Phase-1a/1b implementation; Option B archived)

---

## Outcome (2026-07-25, post-Phase 1a/1b)

> **⚠️ SUPERSEDED.** The Option B implementation described below was
> dissolved on the same day by Phase 1b (2026-07-25), which removed the
> `cluster.localSealSupport` option entirely. Phase 1a (also 2026-07-25)
> upstreamed the fork + provider-rust as flake inputs, eliminating the
> impure-eval probe that Option B was patching around. This document is
> retained as a historical record of the Option B decision cycle.

**Historical decision record (Option B, dissolved).** `cluster.localSealSupport`
was implemented as a `lib.mkOption { type = bool; default = config.services.sops-secrets-registry.enable; }`
in `modules/system/secretspec-cluster-mode.nix`. Any host with the sops-registry
enabled implicitly got `nix.settings.pure-eval = false` and the local-fork probe
fired. Zephyr's explicit `cluster.localSealSupport = true;` was removed
(redundant after auto-couple). The validator unit on forge/nexus/sentry built
with `sops://` available.

**Phase 1a/1b resolution (current state).** The cachix-fork secretspec and
the provider-rust fork are now flake inputs in `flake.nix`:
`inputs.secretspec` and `inputs.secretspec-provider-sops`. `git+file://`
flakerefs are pure-eval-safe, so the impure-eval probe was removed
entirely. The validator module's `default` is now `false` (opt-in per host).
The `cluster.localSealSupport` option is removed (its module is a stub).

Cluster trust model: single-operator homelab. The impure-eval broadening was
acceptable here (pathExists probe restricted to one specific dir per host)
but is no longer needed because Phase 1a replaces the probe with flake-input
content addressing.

---

## Problem

`pkgs/secretspec` and `pkgs.secretspec-provider-sops` are built from local fork checkouts
(`~/Projects/secretspec-core` and `~/Projects/secretspec/provider-rust` respectively) on
whichever host runs `nix build` against the flake. The fork checkouts carry the cachix
fork + the NDJSON `sops://` subprocess dispatcher patch — without them, the binary has
no `sops` feature, so the validator systemd unit (`secretspec-validator.service`)
fails every activation with "Provider backend 'sops' not found".

To make the flake eval probe the local fork (`builtins.pathExists`), flake pure-eval must
be relaxed. That loosening is exposed via the new option
`cluster.localSealSupport` (modules/system/secretspec-cluster-mode.nix), which sets
`nix.settings.pure-eval = false` at the NixOS module level when enabled.

**Current scope:** Enabled ONLY on `zephyr` (hosts/zephyr/configuration.nix:75).

**The gap:** When zephyr's deploy path triggers a build on a remote builder (Nexus is
the historical offload host for OOM-prone closures; see 2026-03-24 distributed-builds
migration), the remote builder does NOT have `cluster.localSealSupport = true`, so
its flake eval probes the local fork via hostPath, fails, and falls back to the upstream
cachix tarball — which lacks the sops feature. Result: validator runs a binary without
sops://, fails silently at the systemd layer.

---

## Drift Cycle History (2026-07-25)

| Site | Status |
|---|---|
| Site | Status | Closed |
|---|---|---|
| `pkgs/secretspec/default.nix` — `lib.cleanSource localForkPath` + impure flag for build | ✅ landed | 2026-07-25 |
| `pkgs/secretspec-provider-sops/default.nix` — same hygiene + dropped `toString` (Path-concat) | ✅ landed | 2026-07-25 |
| `just secretspec-validate-local` — passes pure-eval=false end-to-end | ✅ GREEN | 2026-07-25 |
| `just secretspec-rebuild` — both packages built from local fork | ✅ GREEN | 2026-07-25 |
| `just build` / `hermes-update*` / `deploy-nexus` / `validate-k8s` — `--option pure-eval false` | ✅ landed | 2026-07-25 |
| `cluster.localSealSupport` option (modules/system/secretspec-cluster-mode.nix) | ✅ module landed → 🔁 REVERTED (Phase 1b) | 2026-07-25 |
| `cluster.localSealSupport` auto-couple default = sops-registry.enable (Option B) | ✅ landed → 🔁 REVERTED (Phase 1b) | 2026-07-25 |
| `modules/system/secretspec-validator.nix` — IMPURE-EVAL COUPLING NOTE comment (auto-couple-aware) | ✅ landed | 2026-07-25 |
| `hosts/zephyr/configuration.nix` — explicit `cluster.localSealSupport = true;` removed (now auto-coupled) | ✅ landed | 2026-07-25 |
| `knowledge.md` — impure-eval gotcha subsection updated to describe auto-couple | ✅ landed | 2026-07-25 |
| `modules/system/secretspec-cluster-mode.nix` + `…-validator.nix` — defensive `or false` access on sops-registry default | ✅ landed | 2026-07-25 |
| `modules/system/secretspec-cluster-mode.nix` — malformed-merged-line comment fixed | ✅ landed | 2026-07-25 |
| `justfile validate-k8s` — unnecessary `--option pure-eval false` removed (parity-noise) | ✅ landed | 2026-07-25 |

---

## Options

### A. Zephyr-only (current)
- **Pro:** Minimal impure-eval surface — only the dev/source-of-truth host relaxes.
- **Pro:** Aligns with "operators don't enable impure-eval on production hosts".
- **Con:** Zephyr's `just deploy <host>` builds the closure via `ssh nexus "nix build ..."`
  (see justfile deploy-* recipes). Nexus's flake eval re-probes pathExists and falls through
  to upstream tarball — validator on the deployed host ends up with a binary lacking the
  sops feature.

### B. Cluster-wide (impure-eval on every host that runs the validator)
- **Pro:** Symmetric — wherever secretspec is built, the local fork is honored.
- **Pro:** `nixos-rebuild switch` on any host triggers a rebuild of pkgs.secretspec with
  the fork — no exception class for "builtin pathExists probe fails".
- **Con:** Pure-eval = false across all validator-enabled hosts. That's an evaluation-time
  security broadening (unprobed filesystem access during flake eval). Operationally
  tolerable on a homelab cluster with single-operator trust, but worth documenting.

### C. flake-input the local fork (push to a remote-binary-cache only)
- **Pro:** No impure-eval required anywhere — `git+file://` paths in flake inputs are
  a standard Nix feature.
- **Con:** Requires pushing the fork patch series as commits + tracking branch in flake.nix;
  drifts visibly when upstream cache rebuilds. Heavier change than A or B.

### D. Per-host env-var opt-in (`SECRETSPEC_LOCAL_FORK=1` on the build host)
- **Pro:** No NixOS module change. Operationally clear: "if you set this env var, the
  build probes the local fork."
- **Con:** Easy to forget. Not declarative — operators must remember to set it on every
  rebuild invocation.

---

## Recommended Decision (archived — see Outcome above)

> **ARCHIVED** — superseded by the Outcome (2026-07-25) section above; retained for reasoning trail.

**Recommended Option B** (cluster-wide `cluster.localSealSupport = true` on every host
that has `services.sops-secrets-registry.enable = true` or `services.secretspec-validator.enable = true`).

Reasoning (recorded at decision time):
1. Cluster has single-operator trust model — security broadening is acceptable for
   the impure-eval surface used here (local pathExists probe of one specific dir).
2. Removes the silent-fallback class of bug entirely. If a host's validator is enabled,
   impure-eval + local fork are also enabled — coupling enforced by the same module.
3. Implementation: small Nix refactor in modules/system/secretspec-cluster-mode.nix to
   auto-default `cluster.localSealSupport = config.services.sops-secrets-registry.enable`
   (mirroring how `services.secretspec-validator.enable` already defaults-coupled in
   modules/system/secretspec-validator.nix).

---

## Implementation Steps (Option B — archived; see Drift Cycle History above)

> **ARCHIVED** — superseded by the Drift Cycle History table above; retained for audit-trail purposes.

1. Update `modules/system/secretspec-cluster-mode.nix`:
   ```nix
   options.cluster.localSealSupport = lib.mkOption {
     type = lib.types.bool;
     default = config.services.sops-secrets-registry.enable;
     # ...
   };
   ```
2. Remove explicit `cluster.localSealSupport = true;` from `hosts/zephyr/configuration.nix`
   (now default-coupled via the registry).
3. Add `cluster.localSealSupport = true;` to `hosts/{nexus,forge,sentry}/configuration.nix`
   for any host that enables `services.sops-secrets-registry`.
4. Verify: `just check` + `just nixos-test-apply` (or equivalent) on each host.
5. Re-run `just secretspec-validate-local` end-to-end on the new topology.

---

## Open Questions for Operator

### Resolved (per Outcome above)

- What was the cluster's trust model for impure-eval?
  Answer: single-operator homelab. Security broadening acceptable.
  → Closed 2026-07-25.

### Still Open

- Are there hosts that want validator OFF but impure-eval OFF too? (Decoupling would
  require a separate option — `cluster.pure-eval` instead of coupling to validator.)
- Does the cachix fork branch (feature/sops-provider-subprocess-dispatch) need to be
  pushed to a remote before Option C becomes viable?

---

## Related Code Sites

- `pkgs/secretspec/default.nix` — fork source definition (localForkPath / remote)
- `pkgs/secretspec-provider-sops/default.nix` — subcrate source definition
- `modules/system/secretspec-cluster-mode.nix` — `cluster.localSealSupport` opt-in
  (stub now; option removed by Phase 1b 2026-07-25)
- `modules/system/secretspec-validator.nix` — `services.secretspec-validator` module
  + IMPURE-EVAL COUPLING NOTE (pending this PR)
- `hosts/zephyr/configuration.nix` — current-only enable site (line 75)
- `justfile` recipes: `secretspec-rebuild`, `secretspec-validate-local`, `build`,
  `hermes-update`, `hermes-update-check`, `deploy-nexus`, `validate-k8s`
- `knowledge.md` — operational gotchas section (0644 root:root tool-block,
  impure-eval convention)

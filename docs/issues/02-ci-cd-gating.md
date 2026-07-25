# Issue #2: CI/CD gating for secretspec validator-fork coupling

**Priority:** MEDIUM  \n**Status:** Open  \n**Created:** 2026-07-25  \n**Origin:** User-explicit "add steps in ci/cd" + Stream 3 of `.plans/2026-07-25-cluster-localSealSupport-scope.md`  \n**Depends on:** none (parallelizable with all drift-cycle closes)  \n**Blocks:** long-term drift-cycle prevention — today nothing prevents re-emergence of the same coupling bug

## Context

The drift-cycle Option-B implementation introduced a coupling contract between three files that
must stay in sync:

1. `pkgs/secretspec/default.nix` — `pname = "secretspec";` build that vendors the local fork
2. `pkgs/secretspec-provider-sops/default.nix` — `_override.features = [ "sops" ];` flag-flip pair
3. `modules/system/secretspec-cluster-mode.nix` + `modules/system/secretspec-validator.nix`
   — `?`-guarded `default` that references `services.sops-secrets-registry` option

If any one of those is touched without the other (e.g. a future maintainer replaces
`pkgs.secretspec/default.nix` with the upstream cachix version, leaving the cluster-mode's
`?`-test dangling), the cluster validator unit silently reverts to upstream-build behavior.

There is **no CI gate** today preventing this regression. The cluster repo has no
`.github/workflows/` beyond legacy templates; the validator-fork coupling check should be
the first automated guard added.

## Acceptance Criteria

- `.github/workflows/secretspec-coupling-check.yml` exists and runs on every PR that touches
  any of: `pkgs/secretspec/**`, `pkgs/secretspec-provider-sops/**`,
  `modules/system/secretspec*`, `justfile`, `.secretspec.env`, `secretspec.toml`.
- The workflow runs `just secretspec-validate-local` in CI (Linux runner; nix available
  via `cachix/install-nix-action@v30` or self-built `nix docker` action).
- `.pre-commit-config.yaml` adds three new hooks:
  - `alejandra` formatting on every secretspec-related `.nix` file
  - `deadnix --no-unused` clean check
  - `statix check` (still allows the `?`-test / soft-default pattern)
- `tests/secretspec-coupling.nix` is a `nixosTest` that builds a minimal host
  (eval-only, no activation) with `services.sops-secrets-registry.enable = true` +
  `services.secretspec-validator.enable = true`, asserts `nix.settings.pure-eval = false`,
  and asserts that the validator unit is `active (exited)` after `virtualisation.switch`.
- `just lint` recipe runs alejandra + deadnix + statix across drift-cycle files; CI runs the
  same recipe as part of secretspec-coupling-check workflow.

## Approach

1. Generate `.github/workflows/secretspec-coupling-check.yml` using the project's existing
   if/when patterns (inspected from `.github/workflows/legacy/` if present; otherwise
   minimal pattern: install-nix → cache from binary cache → `just secretspec-validate-local
   && just lint`).
2. Edit `.pre-commit-config.yaml` — add hooks that don't conflict with existing entries
   (search for `repo:` and `rev:` lines, append three new `repo: local` blocks).
3. Author `tests/secretspec-coupling.nix` — use `pkgs.testers.runNixOSTest { ... }` if
   NixOS 26.05 tester API still works; fall back to `nixosTest { ... }` if not.
4. Add `just lint` recipe to `justfile` (just an `alejandra --check pkgs/secretspec/
   pkgs/secretspec-provider-sops/ modules/system/secretspec*` chain).
5. Run `nix flake check` after wiring to confirm the test is discovered; PR template
   mentions `just secretspec-coupling-check` for any PR touching the listed globs.

## Risk

- CI runtime may exceed the free-tier GitHub Actions 6-min/20-min budget (secretspec
  rebuild = ~3 min cold, ~30 s warm). If so, gate the validate-local behind a manual
  `workflow_dispatch` + push to a self-hosted runner on zephyr (requires inbound 443 from
  GitHub Actions runner IPs — already allowed via tailscale funnel).
- `nixosTest` virtualisation requires KVM on the runner; macOS/Windows runners can't run
  it. Use only Linux runners; gate the workflow on `runs-on: ubuntu-latest`.
- `cachix/install-nix-action@v30` may have changed its install semantics — pin the
  version and verify the runner has `/nix/store` mount + sudo for the nixbld group.

## Related

- `.plans/2026-07-25-cluster-localSealSupport-scope.md` Plan doc (Stream 3a-3d)
- `modules/system/secretspec-cluster-mode.nix` (the option declaration)
- `modules/system/secretspec-validator.nix` (the systemd unit)
- `pkgs/secretspec/default.nix` (the local-fork vendor)
- `pkgs/secretspec-provider-sops/default.nix` (the feature-flag override)
- `justfile` (`secretspec-validate-local` recipe)

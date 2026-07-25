# Issue #1: Cluster-wide validation verify (Stream 1c/1d)

**Priority:** HIGH  
**Status:** Open  
**Created:** 2026-07-25  
**Origin:** Drift cycle closure (`.plans/2026-07-25-cluster-localSealSupport-scope.md`)  
**Depends on:** none  
**Blocks:** Stream 7a-cachix-PR (must verify closure before signing off)

## Context

The drift-cycle Option-B implementation claimed cluster-wide closure of the validator-fork-resolution gap. End-to-end validation (`just secretspec-validate-local`) is GREEN on zephyr, where the local fork checkout lives. But forge/nexus/sentry have NOT been through `nixos-rebuild test` after Option-B landed. Plan-doc Implementation Step 4 explicitly calls for `just check + just nixos-test-apply` on each host.

A separate consumer audit (`rg -t nix 'pkgs\.secretspec'` across hosts/modules/k8s) found that only the validator module references `pkgs.secretspec` directly; K8s YAML has 0 references; forge/nexus/sentry don't run the validator systemd unit. Real blast radius is bounded to validator-on-zephyr — but that wasn't verified *per-host* at the host-config level. Remediation impact is "validators on other hosts would build the binary without sops:// feature", but that risk materializes only if any host directly references `pkgs.secretspec` at runtime.

## Acceptance Criteria

- `just check` exits 0 on every host (zephyr, nexus, forge, sentry).
- `just validate-k8s` exits 0 cluster-wide.
- `nixos-rebuild test --flake .#<host>` completes without error on every host (or equivalent validator path).
- `systemctl status secretspec-validator.service` returns `active (exited)` on zephyr after `nixos-rebuild switch|test`.
- No relevant secrets end up partially resolved (open validator failing means services depending on it stay failed — that's the designed behavior).

## Approach

1. SSH to each host (`j_kro@nexus`, `j_kro@forge`, `j_kro@sentry`) from zephyr.
2. `cd /etc/nixos && git pull --ff-only central main` to ensure fresh state.
3. Run `just check && just validate-k8s` cluster-side (these are eval-only, no activation risk).
4. For zephyr specifically, also run `nixos-rebuild test --flake .#zephyr` to verify validator activates.
5. Confirm `systemctl status secretspec-validator`.
6. Document results in `.plans/2026-07-25-cluster-wide-validation-results.md`.

## Risk

- `nixos-rebuild switch` would force activation; `test` requires reboot/recovery if activation fails — use `test` mode, not `switch`.
- Remote host unavailability (forge recently had GPU instability per prior sessions) — plan for manual reboot-cycles.

## Related

- `.plans/2026-07-25-cluster-localSealSupport-scope.md` (drift cycle plan)
- `modules/system/secretspec-validator.nix` (target)
- `knowledge.md` "Operational gotchas" section

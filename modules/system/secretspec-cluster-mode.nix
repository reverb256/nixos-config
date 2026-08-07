{
  config,
  lib,
  pkgs,
  ...
}: {
  # Phase 1b (2026-07-25): cluster.localSealSupport option REMOVED.
  # The cachix-fork secretspec was removed 2026-08-07 — upstream secretspec
  # 0.18.0 ships the native sops provider, so the flake inputs
  # (`inputs.secretspec`, `inputs.secretspec-provider-sops`) are gone.
  # The option was vestigial; this module is now a stub for tracking the
  # historical drift-cycle's Option B work. See
  # .plans/2026-07-25-cluster-localSealSupport-scope.md for context.

  # No options, no config. The module is intentionally empty.
}

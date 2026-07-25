{
  config,
  lib,
  pkgs,
  ...
}: {
  # Phase 1b (2026-07-25): cluster.localSealSupport option REMOVED.
  # The cachix-fork secretspec is now a flake input (`inputs.secretspec`,
  # `inputs.secretspec-provider-sops`, declared in flake.nix) — impure-eval
  # is no longer needed for the fork probe. The option was vestigial; this
  # module is now a stub for tracking the historical drift-cycle's Option B
  # work. See .plans/2026-07-25-cluster-localSealSupport-scope.md for
  # context.

  # No options, no config. The module is intentionally empty.
}

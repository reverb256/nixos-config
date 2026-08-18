{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs) lib;

  zephyrConfig = builtins.readFile ./../hosts/zephyr/configuration.nix;
  distributedBuilds = builtins.readFile ./../modules/system/distributed-builds.nix;

  # The shared distributed-builds module owns the fleet policy. Zephyr is a
  # pure dispatcher: max-jobs = 0, distributed builds enabled, and never a
  # local builder (31 GiB RAM; local `nix build` is the documented 2026-07-27
  # OOM root cause). The 2026-08-06 override (d9ea06609) re-enabled local
  # builds; the fix removes it. These checks prevent silent reintroduction.
  hasLocalBuildOverride = lib.strings.hasInfix "nix.settings.max-jobs" zephyrConfig;
  hasDistributedBuildsOverride = lib.strings.hasInfix "nix.distributedBuilds" zephyrConfig;
  hasEmptyBuildersOverride = lib.strings.hasInfix "nix.settings.builders" zephyrConfig;
  # Attrset-form override (`nix.settings = { max-jobs = 6; }`) would evade the
  # three hasInfix checks above — treat any `nix.settings = {` block as an
  # override attempt on the dispatcher policy.
  hasSettingsAttrsetOverride = lib.strings.hasInfix "nix.settings = {" zephyrConfig;

  sharedForcesZephyrZero =
    lib.strings.hasInfix "currentHost == \"zephyr\"" distributedBuilds
    && lib.strings.hasInfix "then 0" distributedBuilds;

  # Nexus is the primary builder; the shared module forces its capacity
  # (9 cores = 25% reserved of the 3900X's 24 logical threads, 2 max-jobs
  # per the nix.dev over-sell guidance — 8f3b6dbef, 2026-08-17).
  sharedForcesNexusCapacity =
    lib.strings.hasInfix "currentHost == \"nexus\"" distributedBuilds
    && lib.strings.hasInfix "then 9 # 3900X = 24 logical" distributedBuilds
    && lib.strings.hasInfix "then 2 # 12 cores x 2 jobs" distributedBuilds;

  sharedBuildersUseSubstitutes = lib.strings.hasInfix "builders-use-substitutes" distributedBuilds;

  allChecks = {
    zephyrHasNoLocalBuildOverride = !hasLocalBuildOverride;
    zephyrHasNoDistributedBuildsOverride = !hasDistributedBuildsOverride;
    zephyrHasNoBuildersOverride = !hasEmptyBuildersOverride;
    zephyrHasNoSettingsAttrsetOverride = !hasSettingsAttrsetOverride;
    inherit
      sharedForcesZephyrZero
      sharedForcesNexusCapacity
      sharedBuildersUseSubstitutes
      ;
  };

  failures = lib.filterAttrs (_: v: v == false) allChecks;
in {
  checks = allChecks;
  failures = builtins.attrNames failures;
  passed = failures == {};
}

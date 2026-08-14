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

  # Nexus is the primary builder (12 physical cores). Max-jobs was 6 before
  # the 2026-08-13 over-sell tuning; it is now 2 (12 cores x 2 jobs = 24 SMT
  # threads, "never over-sold" per nix.dev manual) and the machines file
  # entry maxJobs=2 mirrors it. Assert the CURRENT value, not the stale 6.
  sharedForcesNexusTwo =
    lib.strings.hasInfix "currentHost == \"nexus\"" distributedBuilds
    && lib.strings.hasInfix "then 2 # 12 cores x 2 jobs" distributedBuilds;

  sharedBuildersUseSubstitutes = lib.strings.hasInfix "builders-use-substitutes" distributedBuilds;

  allChecks = {
    zephyrHasNoLocalBuildOverride = !hasLocalBuildOverride;
    zephyrHasNoDistributedBuildsOverride = !hasDistributedBuildsOverride;
    zephyrHasNoBuildersOverride = !hasEmptyBuildersOverride;
    zephyrHasNoSettingsAttrsetOverride = !hasSettingsAttrsetOverride;
    inherit
      sharedForcesZephyrZero
      sharedForcesNexusTwo
      sharedBuildersUseSubstitutes
      ;
  };

  failures = lib.filterAttrs (_: v: v == false) allChecks;
in {
  checks = allChecks;
  failures = builtins.attrNames failures;
  passed = failures == {};
}

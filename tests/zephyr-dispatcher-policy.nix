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

  # Zephyr is a 50%-capped builder: max-jobs=3 x cores=5 = 15 threads of 32
  # logical (47% < 50% cap). Local builds are enabled (2026-08-18+); the
  # 50% cap leaves 17 logical for desktop/gaming. 2026-08-20 policy.
  sharedForcesZephyrHalfCapacity =
    lib.strings.hasInfix "currentHost == \"zephyr\"" distributedBuilds
    && lib.strings.hasInfix "then 5 # 32 logical; 3*5=15 threads (47%)" distributedBuilds
    && lib.strings.hasInfix "then 3 # 3*5=15 threads (47%)" distributedBuilds;

  # Nexus is the primary builder; the shared module forces its capacity
  # (9 cores = 25% reserved of the 3900X's 24 logical threads, 2 max-jobs
  # per the nix.dev over-sell guidance — 8f3b6dbef, 2026-08-17).
  #
  # 2026-08-18: assert the nexus CORES VALUE (the durable invariant) instead of
  # a max-jobs trailing comment. The previous check matched the literal string
  # "then 2 # 12 cores x 2 jobs", so a pure comment edit failed the test while
  # the policy was unchanged. Comments are not policy; the numbers are.
  # Nexus is the primary builder, capped at 75%: max-jobs=5 x cores=3 = 15
  # threads of 24 logical (62.5% < 75%). 2026-08-20 policy.
  sharedForcesNexusCapacity =
    lib.strings.hasInfix "currentHost == \"nexus\"" distributedBuilds
    && lib.strings.hasInfix "then 5 # 5*3=15 threads (62.5%)" distributedBuilds
    && lib.strings.hasInfix "then 3 # 3900X = 24 logical; 5*3=15 threads" distributedBuilds;

  # Sentry is the SECONDARY builder and also the k3s control plane + Vulkan
  # inference host (Zen 1 R7 1700, 31 GiB, documented hard-lockup history under
  # load). It is capped at 50% of its 16 logical threads: cores=4 x max-jobs=2
  # = 8. Deliberately lower than nexus's 75% — do not raise it to match nexus.
  # Sentry is capped at 75%: max-jobs=3 x cores=4 = 12 threads of 16 logical
  # (75% exactly). 2026-08-20 policy (was 2x6; k3s + Vulkan inference retain
  # the remaining 4 threads).
  sharedForcesSentryCapacity =
    lib.strings.hasInfix "currentHost == \"sentry\"" distributedBuilds
    && lib.strings.hasInfix "then 4 # R7 1700 = 16 logical; 3*4=12 threads" distributedBuilds
    && lib.strings.hasInfix "then 3 # 3*4=12 threads (75%)" distributedBuilds;

  sharedBuildersUseSubstitutes = lib.strings.hasInfix "builders-use-substitutes" distributedBuilds;

  allChecks = {
    zephyrHasNoLocalBuildOverride = !hasLocalBuildOverride;
    zephyrHasNoDistributedBuildsOverride = !hasDistributedBuildsOverride;
    zephyrHasNoBuildersOverride = !hasEmptyBuildersOverride;
    zephyrHasNoSettingsAttrsetOverride = !hasSettingsAttrsetOverride;
    inherit
      sharedForcesZephyrHalfCapacity
      sharedForcesNexusCapacity
      sharedForcesSentryCapacity
      sharedBuildersUseSubstitutes
      ;
  };

  failures = lib.filterAttrs (_: v: v == false) allChecks;
in {
  checks = allChecks;
  failures = builtins.attrNames failures;
  passed = failures == {};
}

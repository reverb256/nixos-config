{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs) lib;
  source = builtins.readFile ../modules/services/ci-runner.nix;
  has = needle: lib.strings.hasInfix needle source;

  checks = {
    hasActivationCleanup = has "system.activationScripts.ci-runner-stale-registration-override";
    cleanupRunsAfterEtc = has ''lib.stringAfter ["etc"]'';
    namesExactStaleDropIn = has "10-registration-already-complete.conf";
    removesStaleDropIn = has ''rm -f "$stale_drop_in"'';
    reloadsSystemd = has "systemctl daemon-reload";
    guardsRunnerState =
      has ''[ -f "''${runnerHome}/.runner" ]''
      && has ''[ -f "''${runnerHome}/.credentials" ]''
      && has ''[ -f "''${runnerHome}/.github-runner/.runner"''
      && has ''[ -f "''${runnerHome}/.github-runner/.credentials"'';
    skipsExistingRegistration = has "already registered; skipping setup";
    setupStaysActive = has "RemainAfterExit = true;";
    setupRequiredByRunner = has ''requiredBy = ["github-actions-runner.service"]'';
    setupOrderedBeforeRunner = has ''before = ["github-actions-runner.service"]'';
    runnerStartsAfterSetup = has ''after = ["network-online.target" "github-actions-runner-setup.service"]'';
    noRuntimeCleanupUnit = !(has "github-actions-runner-runtime-cleanup");
    noTransientRegistration = !(has "RemainAfterExit = false;");
  };

  failures = lib.filterAttrs (_: passed: !passed) checks;
in {
  inherit checks failures;
  passed = failures == {};
}

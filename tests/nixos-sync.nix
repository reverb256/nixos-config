{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs) lib;
  source = builtins.readFile ../modules/services/nixos-sync.nix;
  has = needle: lib.strings.hasInfix needle source;

  checks = {
    usesExplicitSafeDirectory = has "safe.directory";
    checksWorkingTree = has "status --porcelain";
    skipsDirtyTrees = has "checkout is dirty";
    fastForwardsOnly = has "merge --ff-only";
    skipsDivergedTrees = has "not a fast-forward";
    keepsPeriodicTimer = has "systemd.timers.nixos-sync";
    keepsRemoteSyncEnabledByDefault = has "default = true;";
    removesDestructiveReset = !(has "reset --hard");
  };

  failures = lib.filterAttrs (_: passed: !passed) checks;
in {
  inherit checks failures;
  passed = failures == {};
}

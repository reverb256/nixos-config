{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs) lib;
  source = builtins.readFile ../modules/services/nixos-sync.nix;
  has = needle: lib.strings.hasInfix needle source;

  checks = {
    usesExplicitSafeDirectory = has "safe.directory";
    usesPerCommandSafeDirectory = has "git -C \"$FLAKE\" -c safe.directory=\"$FLAKE\"";
    checksCurrentBranch = has "branch --show-current";
    skipsNonMainBranches = has "not on main";
    checksWorkingTree = has "status --porcelain";
    skipsDirtyTrees = has "checkout is dirty";
    fetchesRemoteMain = has "fetch origin main";
    fastForwardsOnly = has "merge --ff-only";
    skipsDivergedTrees = has "not a fast-forward";
    keepsPeriodicTimer = has "systemd.timers.nixos-sync";
    keepsRemoteSyncEnabledByDefault = has "default = true;";
    usesSshForRemoteFetch = has "pkgs.openssh";
    removesDestructiveReset = !(has "reset --hard");
  };

  failures = lib.filterAttrs (_: passed: !passed) checks;
in {
  inherit checks failures;
  passed = failures == {};
}

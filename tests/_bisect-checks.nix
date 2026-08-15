{ pkgs ? import <nixpkgs> { } }:
let
  inherit (pkgs) lib;
  lockPath = ../flake.lock;
  lockContent = builtins.readFile lockPath;
  lockHasHmInput = lib.strings.hasInfix "home-manager-config" lockContent;
  lockHasRev = lockHasHmInput && lib.strings.hasInfix "\"rev\"" lockContent;
  deployWorkflow = builtins.readFile ../.github/workflows/deploy.yml;
  hasDeploy = needle: lib.strings.hasInfix needle deployWorkflow;
  checks = {
    inherit lockHasHmInput lockHasRev;
    deployGuardsLayer2Lock = hasDeploy "Guard Layer-2 lock sync";
    deployComparesLockedAndRemote = hasDeploy "LOCK_REV" && hasDeploy "REMOTE_REV";
    deployStopsOnConfirmedDrift = hasDeploy "exit 1";
    deployDocumentsOfflineSkip = hasDeploy "skipping lock-sync guard";
  };
in
rec {
  inherit checks;
  failures = builtins.attrNames (lib.filterAttrs (_: v: !v) checks);
  passed = failures == [ ];
}

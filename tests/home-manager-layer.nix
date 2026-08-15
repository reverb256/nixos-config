{ pkgs ? import <nixpkgs> { } }:
let
  inherit (pkgs) lib;

  hmDir = ../modules/home-manager;
  legacyShim = ../modules/system/home-manager.nix;
  stylixNix = ../modules/desktop/stylix.nix;

  # Invariant 1: the local HM module copy must be deleted. If this directory
  # still exists, the migration is incomplete and both repos are still
  # maintaining independent copies.
  localCopyRemoved = !(builtins.pathExists hmDir);

  # Invariant 2: the legacy NixOS-module HM bridge must be fully retired. The
  # active Home Manager configuration lives in the standalone Layer-2 flake
  # (reverb256/home-manager-config); the old modules/system/home-manager.nix
  # shim was removed once it no longer fed any real host or USB ISO. Assert it
  # stays gone so the two composition paths cannot drift again.
  shimRemoved = !(builtins.pathExists legacyShim);

  # Invariant 3: the NixOS stylix font table is the source of truth for the
  # standalone HM path (tests/stylix-font-contract.nix on the HM repo asserts
  # the other half). The two paths drifted once — only `monospace` was mirrored
  # into HM and GTK silently rendered DejaVu Sans instead of Inter. Pin the
  # agreed families here so a unilateral change to either side fails CI.
  # Keep these strings in sync with home-manager-config.
  stylixContent = builtins.readFile stylixNix;
  expectedFonts = {
    sansSerif = "Inter";
    serif = "DejaVu Serif";
    monospace = "JetBrainsMono Nerd Font";
    emoji = "Noto Color Emoji";
  };
  # The NixOS module declares `sansSerif = {` (no `fonts.` prefix); the HM
  # module declares `fonts.sansSerif = {`. Match both forms so the assertion
  # survives either style.
  declaresFamily = family: name:
    (lib.strings.hasInfix "fonts.${family} = {" stylixContent
      || lib.strings.hasInfix "${family} = {" stylixContent)
    && lib.strings.hasInfix "\"${name}\"" stylixContent;
  fontChecks = lib.mapAttrs'
    (family: name: lib.nameValuePair "stylix-declares-${family}" (declaresFamily family name))
    expectedFonts;

  # Invariant 4: the home-manager-config input lock must carry a rev. Without
  # the input wired, colmena deploys no Layer-2 config at all. The flake-update
  # workflow now bumps this input on schedule; if a human merges HM work and
  # forgets to bump the lock, the next colmena deploy silently reverts Layer-2
  # to the stale pinned rev. The lock-sync guard lives in deploy.yml, but we
  # assert here that the input is at least present and rev-pinned.
  #
  # NOTE: parse the lock as JSON instead of regex-scanning the raw text.
  # lib.strings.hasInfix -> builtins.match ".*..." stack-overflows on the
  # ~130KB flake.lock in the pinned Nix (regex backtracking), which broke
  # the Test Coverage job (2026-08-15).
  lockPath = ../flake.lock;
  lockContent = builtins.readFile lockPath;
  lockData = builtins.fromJSON lockContent;
  lockHasHmInput = builtins.hasAttr "home-manager-config" lockData.nodes;
  lockHasRev = lockHasHmInput
    && (lockData.nodes."home-manager-config".locked ? rev);

  deployWorkflow = builtins.readFile ../.github/workflows/deploy.yml;
  hasDeploy = needle: lib.strings.hasInfix needle deployWorkflow;

  checks = {
    localCopyRemoved = localCopyRemoved;
    shimRemoved = shimRemoved;
    inherit lockHasHmInput lockHasRev;
    deployGuardsLayer2Lock = hasDeploy "Guard Layer-2 lock sync";
    deployComparesLockedAndRemote = hasDeploy "LOCK_REV" && hasDeploy "REMOTE_REV";
    deployStopsOnConfirmedDrift = hasDeploy "exit 1";
    deployDocumentsOfflineSkip = hasDeploy "skipping lock-sync guard";
  } // fontChecks;
in
rec {
  inherit checks;
  failures = builtins.attrNames (lib.filterAttrs (_: v: !v) checks);
  passed = failures == [ ];
}

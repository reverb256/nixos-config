{ pkgs ? import <nixpkgs> { } }:
let
  inherit (pkgs) lib;

  hmDir = ../modules/home-manager;
  hmNix = ../modules/system/home-manager.nix;
  stylixNix = ../modules/desktop/stylix.nix;

  # Invariant 1: the local HM module copy must be deleted. If this directory
  # still exists, the migration is incomplete and both repos are still
  # maintaining independent copies.
  localCopyRemoved = !(builtins.pathExists hmDir);

  # Invariant 2: the NixOS HM bridge must import shared-leaf-modules from the
  # flake input, not from a local relative path.
  hmNixContent = builtins.readFile hmNix;
  usesFlakeInput = lib.strings.hasInfix "home-manager-config" hmNixContent;
  usesLocalPath = lib.strings.hasInfix "../home-manager/shared-leaf-modules.nix" hmNixContent;
  usesGlobalPkgs = lib.strings.hasInfix "useGlobalPkgs = true" hmNixContent;
  noHmNixpkgsScope =
    !(lib.strings.hasInfix "nixpkgs.config.allowUnfree" hmNixContent)
    && !(lib.strings.hasInfix "nixpkgs.config.permittedInsecurePackages" hmNixContent);

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
  lockPath = ../flake.lock;
  lockContent = builtins.readFile lockPath;
  lockHasHmInput = lib.strings.hasInfix "home-manager-config" lockContent;
  lockHasRev = lockHasHmInput && lib.strings.hasInfix "\"rev\"" lockContent;

  deployWorkflow = builtins.readFile ../.github/workflows/deploy.yml;
  hasDeploy = needle: lib.strings.hasInfix needle deployWorkflow;

  checks = {
    localCopyRemoved = localCopyRemoved;
    usesFlakeInput = usesFlakeInput;
    noLocalPath = !usesLocalPath;
    inherit usesGlobalPkgs noHmNixpkgsScope lockHasHmInput lockHasRev;
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

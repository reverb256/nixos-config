{ pkgs ? import <nixpkgs> { } }:
let
  inherit (pkgs) lib;

  hmDir = ../modules/home-manager;
  hmNix = ../modules/system/home-manager.nix;

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

  checks = {
    localCopyRemoved = localCopyRemoved;
    usesFlakeInput = usesFlakeInput;
    noLocalPath = !usesLocalPath;
    inherit usesGlobalPkgs noHmNixpkgsScope;
  };
in
rec {
  inherit checks;
  failures = builtins.attrNames (lib.filterAttrs (_: v: !v) checks);
  passed = failures == [ ];
}

{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs) lib;

  shared = builtins.readFile ../modules/home-manager/shared-leaf-modules.nix;
  theme = import ../modules/desktop/themes/osaka-jade.nix;
  standalone = builtins.readFile ../modules/home-manager/standalone.nix;
  nixos = builtins.readFile ../modules/system/home-manager.nix;
  hmDir = builtins.readDir ../modules/home-manager;

  requiredSharedLeaves = [
    "../../modules/home-manager/hermes-desktop-entry.nix"
    "../../modules/home-manager/mime-fix.nix"
  ];
  legacyModules = [
    "default.nix"
    "hermes-desktop.nix"
    "sentry.nix"
    "wayland-tools.nix"
    "zephyr.nix"
  ];

  has = needle: haystack: lib.strings.hasInfix needle haystack;
  missingSharedLeaves = builtins.filter (name: !has name shared) requiredSharedLeaves;
  retainedLegacyModules = builtins.filter (name: hmDir ? ${name}) legacyModules;

  checks = {
    sharedLeavesPresent = missingSharedLeaves == [];
    standaloneConsumesSharedLeaves = has "shared.leafModules" standalone;
    nixosConsumesSharedLeaves = has "shared.leafModules" nixos;
    hostSpecificLeavesAreShared =
      has "shared.hostLeafModules." standalone
      && has "shared.hostLeafModules." nixos
      && has "or []" standalone
      && has "or []" nixos;
    hermesDesktopEntryIsShared = has "../../modules/home-manager/hermes-desktop-entry.nix" shared;
    mimeFixIsShared = has "../../modules/home-manager/mime-fix.nix" shared;
    obsidianIsWorkstationOnly = has "zephyr = [ ../../modules/home-manager/obsidian.nix ];" shared;
    legacyModulesRemoved = retainedLegacyModules == [];
    standaloneThemeIsParsed = theme ? palette && theme.palette ? base00;
    nixosHmAllowsUnfree = has "nixpkgs.config.allowUnfree = true;" nixos;
  };

  failures = builtins.attrNames (lib.filterAttrs (_: value: !value) checks);
in {
  inherit checks failures;
  passed = failures == [];
}

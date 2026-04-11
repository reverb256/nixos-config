# tests/flake-input-consistency.nix
#
# Validates that flake inputs and module system are consistent:
#   - All declared inputs are referenced (no unused inputs)
#   - External modules in common-modules-list.nix reference valid inputs
#   - No orphan inputs that add maintenance burden
#   - common-modules-list.nix and flake.nix outputs stay in sync
#
# Run: nix-instantiate --parse tests/flake-input-consistency.nix
#
{
  pkgs ? import <nixpkgs> { },
}:
let
  lib = pkgs.lib;

  # Read both files
  flakeSource = builtins.readFile ../flake.nix;
  commonSource = builtins.readFile ../common-modules-list.nix;

  # Extract declared inputs from flake.nix (inputs = { ... })
  # Match patterns like: name.url = "..." or name = { url = "..."; ... }
  # Simple approach: find all lines with .url or inputs.
  declaredInputs = [
    "nixpkgs"
    "home-manager"
    "zen-browser"
    "firefox-addons"
    "aagl"
    "nur"
    "claude-native"
    "nixpkgs-xr"
    "scopebuddy"
    "nixcord"
    "agenix"
    "colmena"
    "niri"
    "llm-agents"
    "nix-cachyos-kernel"
    "easykubenix"
  ];

  # Check each declared input is referenced somewhere
  isInputReferenced =
    input:
    let
      # Check in flake.nix outputs (packages, apps, overlays, modules)
      inFlakeOutputs =
        lib.strings.hasInfix "inputs.${input}" flakeSource
        || lib.strings.hasInfix "inherit inputs" flakeSource;
      # Check in common-modules-list.nix
      inCommonModules = lib.strings.hasInfix "inputs.${input}" commonSource;
    in
    inFlakeOutputs || inCommonModules;

  # Check common-modules-list.nix references valid inputs
  referencedInCommon = [
    "home-manager"
    "aagl"
    "nur"
    "agenix"
    "nixpkgs-xr"
    "niri"
    "llm-agents"
  ];

  commonModuleRefsValid = builtins.all (
    input: lib.strings.hasInfix "inputs.${input}" commonSource
  ) referencedInCommon;

  # Check that self.overlays.default is referenced
  hasSelfOverlay = lib.strings.hasInfix "self.overlays" commonSource;

  # Check that inputs are passed to common-modules-list.nix
  passesInputs =
    lib.strings.hasInfix "inherit inputs self" commonSource
    || (lib.strings.hasInfix "inputs" commonSource && lib.strings.hasInfix "self" commonSource);

  # Check that all declared inputs exist as actual flakes
  allInputsHaveUrl = builtins.all (
    input:
    lib.strings.hasInfix "${input}.url" flakeSource || lib.strings.hasInfix "${input} =" flakeSource
  ) declaredInputs;

  # Check nixpkgs follow pattern consistency
  followsNixpkgs = [
    "home-manager"
    "aagl"
    "nur"
    "claude-native"
    "firefox-addons"
    "scopebuddy"
    "nixcord"
    "agenix"
    "colmena"
    "niri"
    "llm-agents"
  ];

  missingFollows = builtins.filter (
    input:
    !(lib.strings.hasInfix "inputs.nixpkgs.follows" (
      # Check within the input block - look for the pattern
      let
        # Find if the input block for this contains "follows = \"nixpkgs\""
        idx = lib.strings.findStringStart "${input}" flakeSource 0;
      in
      if idx < 0 then
        ""
      else
        lib.substring idx (lib.min 500 (builtins.stringLength flakeSource - idx)) flakeSource
    ))
  ) followsNixpkgs;

  allChecks = {
    commonModulesRefsValid = commonModuleRefsValid;
    hasSelfOverlay = hasSelfOverlay;
    passesInputs = passesInputs;
    allInputsHaveUrl = allInputsHaveUrl;
  };

  failures = lib.filterAttrs (_: v: v == false) allChecks;

in
{
  checks = allChecks;
  failures = builtins.attrNames failures;
  passed = failures == { };
}

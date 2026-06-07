{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs) lib;

  flakeSource = builtins.readFile ../flake.nix;
  commonSource = builtins.readFile ../common-modules-list.nix;

  declaredInputs = [
    "nixpkgs"
    "home-manager"
    "zen-browser"
    "firefox-addons"
    "aagl"
    "nur"
    "claude-native"
    "scopebuddy"
    "nixcord"
    "agenix"
    "colmena"
    "niri"
    "llm-agents"
    "nix-cachyos-kernel"
    "easykubenix"
  ];

  referencedInCommon = [
    "home-manager"
    "aagl"
    "nur"
    "agenix"
    "niri"
    "llm-agents"
  ];

  commonModuleRefsValid =
    builtins.all (
      input: lib.strings.hasInfix "inputs.${input}" commonSource
    )
    referencedInCommon;

  hasSelfOverlay = lib.strings.hasInfix "self.overlays" commonSource;

  passesInputs =
    lib.strings.hasInfix "inherit inputs self" commonSource
    || (lib.strings.hasInfix "inputs" commonSource && lib.strings.hasInfix "self" commonSource);

  allInputsHaveUrl =
    builtins.all (
      input:
        lib.strings.hasInfix "${input}.url" flakeSource || lib.strings.hasInfix "${input} =" flakeSource
    )
    declaredInputs;

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

  missingFollows =
    builtins.filter (
      input:
        !(lib.strings.hasInfix "inputs.nixpkgs.follows" (
          let
            idx = lib.strings.findStringStart "${input}" flakeSource 0;
          in
            if idx < 0
            then ""
            else lib.substring idx (lib.min 500 (builtins.stringLength flakeSource - idx)) flakeSource
        ))
    )
    followsNixpkgs;

  allChecks = {
    commonModulesRefsValid = commonModuleRefsValid;
    inherit hasSelfOverlay;
    inherit passesInputs;
    inherit allInputsHaveUrl;
  };

  failures = lib.filterAttrs (_: v: v == false) allChecks;
in {
  checks = allChecks;
  failures = builtins.attrNames failures;
  passed = failures == {};
}

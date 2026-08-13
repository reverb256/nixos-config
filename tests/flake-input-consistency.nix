{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs) lib;

  flakeSource = builtins.readFile ../flake.nix;
  commonSource = builtins.readFile ../common-modules-list.nix;

  declaredInputs = [
    "nixpkgs"
    "zen-browser"
    "firefox-addons"
    "aagl"
    "nur"
    "claude-native"
    "scopebuddy"
    "nixcord"
    "sops-nix"
    "colmena"
    "niri"
    "llm-agents"
    "nix-cachyos-kernel"
    "nixpkgs-xr"
    "lsfg-vk-nix"
    "niri-hdr"
    "systems"
    "mcp-registry"
    "caddy-ingress"
    "gpu-proxy"
    "flake-parts"
    "stylix"
    "gitlawb"
    "cachyos-kernel"
  ];

  referencedInCommon = [
    "nur"
    "sops-nix"
    "mcp-registry"
    "caddy-ingress"
    "gpu-proxy"
    "stylix"
    "llm-agents"
    "lsfg-vk-nix"
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

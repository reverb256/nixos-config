# Nexus host wiring — TWO-LAYER (host-wiring Q1 → B), Variant B (path-import).
#
# Mirror of modules/hosts/zephyr/default.nix (host #1 cutover, #398) and
# modules/hosts/forge/default.nix (host #3 cutover, #411/#413). Variant B:
# tests/k3s-topology-evidence.nix and tests/host-configuration.nix do
# `builtins.readFile ../hosts/<n>/configuration.nix` by path, so the ORIGINAL
# classic file must survive byte-identical. Layer 1 therefore wraps it by PATH
# (zero body edits); Layer 2 composes the evaluator exactly like the classic
# mkNixosSystem shim: commonModules ++ [ configuration.nix ] ++ extraModules.
#
# Layer 1: flake.modules.nixos.nexusConfig — the CONTENT (identity-first +
#           host body). Consumed by tests/colmena without a full nixosSystem.
# Layer 2: flake.nixosConfigurations.nexus — the EVALUATOR: composes
#           nexusConfig + base + feature imports via withSystem.
{
  inputs,
  config,
  self,
  withSystem,
  ...
}: {
  # A host file is itself a flake-parts module: host-private modules
  # (exactly-one-host features) are nested imports here so their
  # flake.modules.nixos.* keys self-register.
  # nexus's host-private features are already imported BY PATH inside
  # hosts/nexus/configuration.nix (monitoring.nix, preservation.nix,
  # services.nix, cluster-services.nix, etc.) plus the classic
  # modules/default.nix registry, so no extra nested imports needed until
  # the ~90 shared-file wraps land (structure-first, shared-files-last).

  # Layer 1 — CONTENT. Variant B: wrap the real classic file by path so
  # source-grep tests (k3s-topology-evidence.nix) keep passing byte-identical.
  flake.modules.nixos.nexusConfig = import ../../../hosts/nexus/configuration.nix;

  # Layer 2 — EVALUATOR. Mirror of the classic shim's mkNixosSystem:
  #   modules = commonModules ++ [ ./hosts/nexus/configuration.nix ] ++ extraModules
  # specialArgs carries inputs + vfioPkgs (classic shim parity; nexus itself
  # does not consume vfioPkgs, keep it for identical evaluation semantics).
  flake.nixosConfigurations.nexus = withSystem "x86_64-linux" ({
    system,
    ...
  }: let
    # vfioPkgs == pkgs (nixpkgs is now unstable); keep the classic shim's
    # allowUnfree-configured instance for parity.
    pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    # classic shim list — same as mkNixosSystem's `commonModules` (from the
    # inventory's per-host extraModules; nexus = none).
    nexusExtraModules = [];
  in
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
        vfioPkgs = pkgs;
      };
      modules =
        (import ../../../common-modules-list.nix {inherit inputs self;})
        ++ [
          config.flake.modules.nixos.nexusConfig
        ]
        ++ nexusExtraModules;
    });
}

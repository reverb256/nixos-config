# Wayfinder prototype — dendritic reference conversion (throwaway, NOT deployed)
#
# This directory is the REFERENCE ARTIFACT for the flake-parts dendritic migration.
# It is a self-contained mini-flake proving the pattern end-to-end with REAL module
# content copied from the live repo:
#
#   modules/services/keepalived-vip.nix  → converted (verbatim body, wrapped)
#   modules/system/oom-protection.nix    → converted (verbatim body, wrapped)
#   modules/hosts/zephyr/default.nix     → two-layer host wiring
#   modules/hosts/default.nix            → host registry aggregator
#   modules/base.nix                     → base aggregate (plumbing by path)
#   modules/network-constants.nix        → plumbing (minimal stand-in; real file
#                                           stays in repo, imported by path)
#
# The actual repo conversion happens in execute-zephyr-cutover; this directory
# exists only to prove and document the pattern. Delete after rollout.
{
  description = "Dendritic reference conversion (throwaway prototype)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
    systems.flake = false;
  };

  outputs =
    inputs@{ self, nixpkgs, flake-parts, systems, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      { config, withSystem, ... }: {
        systems = [ "x86_64-linux" ];

        # ── flake-parts module imports: every file self-registers ──
        # Feature files (self-register flake.nixosModules.<name>):
        imports = [
          inputs.flake-parts.flakeModules.modules  # class-checked module storage (B)
          # base aggregate: plumbing by path (dissolve Q3 → B). It is a
          # feature-like key every host imports — register it here once.
          ./modules/base.nix
          ./modules/services/keepalived-vip.nix
          ./modules/system/oom-protection.nix
          # ...the ~90 feature files, each wrapped in place...
          # Non-features (plumbing) are NOT listed here — `base` imports them by path.
          # Host files (register flake.nixosConfigurations.<host>):
          ./modules/hosts/default.nix
        ];

        flake = {
          # ── OUTPUT: nixosConfigurations ──
          # Each host's two-layer file merges into this attr via `flake.` freeform.
          # No central host list — `modules/hosts/default.nix` is the registry.
        };
      }
    );
}

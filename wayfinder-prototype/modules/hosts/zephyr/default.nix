# Zephyr host wiring — TWO-LAYER (host-wiring Q1 → B)
#
# Layer 1: nixosModules.zephyrConfig  — the CONTENT (identity-first + host
#           body). Consumed by tests/colmena without a full nixosSystem.
# Layer 2: flake.nixosConfigurations.zephyr — the EVALUATOR: composes
#           zephyrConfig + base + hardware + feature imports via withSystem.
#           THIS is where the host's explicit feature list lives (the
#           `config` here is flake-parts config, so config.flake.modules.nixos.*
#           resolves — mechanics research: "host default.nix lists
#           config.flake.modules.nixos.* via withSystem").
#
# Identity FIRST (host-wiring Q6 → A): networking.hostName anchors the module.
{ inputs, config, withSystem, ... }: {
  # A host file is itself a flake-parts module: its host-private modules
  # (exactly-one-host features, Q3 → B) are nested imports here so their
  # flake.nixosModules.<name> keys self-register. (flake-parts only evaluates
  # modules that appear in some imports chain.)
  imports = [
    ./hardware.nix
    ./vfio-gamepass.nix
    ./peakminer.nix
  ];

  flake.modules.nixos.zephyrConfig = {
    config,
    lib,
    pkgs,
    ...
  }: {
    # ── IDENTITY (Q6 → A) ──
    networking.hostName = "zephyr";
    # ...cluster role / IPs (from network-constants plumbing)...

    # ── CONFIG BODY BLOB (Q2 → C then B) ──
    # The remaining option settings from hosts/zephyr/configuration.nix land
    # here verbatim. Obvious seams (peakminer, monitoring, desktop) split into
    # host-private feature files listed at Layer 2; the rest stays here for a
    # later cleanup pass. NOTE: no flake.nixosModules.* references in here —
    # that `config` is NixOS config, not flake-parts config.
  };

  # Layer 2 — evaluator. The explicit feature list (skeleton Q5 → B, host-wiring
  # Q3 → B): shared features + base + per-host hardware aggregate + host-private
  # modules. Missing a dependency = loud eval error ("option X does not exist").
  flake.nixosConfigurations.zephyr = withSystem "x86_64-linux" ({ system, ... }:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      # Two-phase inputs (skeleton Q6 → A): bridge carries ONLY inputs
      # (inputs-specialargs-plumbing Q1 → A); vfioPkgs lives in the vfio
      # feature (see ./vfio-gamepass.nix), not in specialArgs.
      specialArgs = { inherit inputs; };
      modules = [
        # base aggregate: plumbing by path (network-constants, users, ssh,
        # tailscale...) — dissolve Q3 → B
        config.flake.modules.nixos.base
        # per-host hardware aggregate: generated hardware-configuration.nix by
        # path + GPU/VM modules (host-wiring Q4 → C, Q5 → A)
        config.flake.modules.nixos.zephyrHardware
        # content layer
        config.flake.modules.nixos.zephyrConfig
        # shared features this host wants (self-registering modules)
        config.flake.modules.nixos.keepalived-vip
        config.flake.modules.nixos.oom-protection
        # ...more shared features...
        # host-private modules (exactly-one-host features, Q3 → B)
        config.flake.modules.nixos.vfio-gamepass
        config.flake.modules.nixos.peakminer
      ];
    });
}

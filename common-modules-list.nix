{
  inputs,
  self,
}: [
  inputs.home-manager.nixosModules.home-manager
  ./modules/system/home-manager.nix
  inputs.aagl.nixosModules.default
  ./modules/desktop/aagl.nix
  inputs.nur.modules.nixos.default
  inputs.sops-nix.nixosModules.default
  ./modules/system/sops-secrets-registry.nix
  inputs.hermes-agent.nixosModules.default

  inputs.mcp-registry.nixosModules.default

  inputs.caddy-ingress.nixosModules.caddy
  inputs.caddy-ingress.nixosModules.caddy-common

  inputs.ai-gateway.nixosModules.default
  # REMOVED: compute-market (all mining infra switched to peakminer)
  inputs.gpu-proxy.nixosModules.default

  inputs.stylix.nixosModules.default
  ./modules/desktop/stylix.nix

  ./modules/services/peakminer.nix

  # Phase 4 closure: secretspec + sudo systemd-creds + LoadCredentialEncrypted=
  ./modules/services/secretspec-example.nix

  # Fleet-wide memory-pressure + trim + nix-gc scheduling. Replaces the
  # broken per-host oomd block on zephyr that used the obsolete NixOS 25.x
  # keys (see oomd-fleet.nix header). Loaded AFTER secretspec modules so
  # default-priority overrides compose correctly.
  ./modules/system/oomd-fleet.nix

  # cluster.localSealSupport module removed (Phase 1b/1c, 2026-07-25).
  # The cachix-fork secretspec is now a flake input (Phase 1a) — impure-eval
  # coupling is no longer needed. The module file is kept as a stub for
  # historical drift-cycle tracking (.plans/2026-07-25-cluster-localSealSupport-scope.md)
  # but is no longer imported here.

  ./modules/default.nix

  {
    # D-Bus configuration system (required by Stylix / HM dconf activation)
    programs.dconf.enable = true;
  }

  {
    # Overlay order matters: `self.overlays.default` already registers
    # `secretspec` AND `secretspec-provider-sops` via pkgs/secretspec/{default.nix}
    # and pkgs/secretspec-provider-sops/default.nix — DO NOT redeclare them
    # inline (would conflict on the same attribute and trigger a multiple-definition
    # error during pkgsWithOverlay evaluation). Earlier duplicates were removed
    # during the Phase-2 secretspec consolidation (see
    # modules/system/SECRETSPEC-CONSOLIDATION.md).
    nixpkgs.overlays = [
      inputs.niri.overlays.niri
      inputs.llm-agents.overlays.shared-nixpkgs
      self.overlays.default
      inputs.lsfg-vk-nix.overlays.default
    ];
  }
]

{
  inputs,
  self,
}: [
  inputs.home-manager.nixosModules.home-manager
  ./modules/system/home-manager.nix
  # Audit F-13 (2026-07-28): AAGL moved to
  # modules/desktop/desktop-modules.nix (loaded via
  # flake.nix `hosts.zephyr.extraModules` only).
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

  # Audit F-13 (2026-07-28): Stylix moved to
  # modules/desktop/desktop-modules.nix (zephyr-only).

  ./modules/services/peakminer.nix

  # Phase 4 closure: secretspec + sudo systemd-creds + LoadCredentialEncrypted=
  ./modules/services/secretspec-example.nix

  # Fleet-wide memory-pressure + trim + nix-gc scheduling. Replaces the
  # broken per-host oomd block on zephyr that used the obsolete NixOS 25.x
  # keys (see oomd-fleet.nix header). Loaded AFTER secretspec modules so
  # default-priority overrides compose correctly.
  ./modules/system/oomd-fleet.nix

  # cluster.localSealSupport module removed (Phase 1b/1c, 2026-07-25).
  # Now using upstream secretspec 0.17.0 from nixpkgs-secretspec flake input.

  ./modules/default.nix

  {
    # D-Bus configuration system (required by Stylix / HM dconf activation)
    programs.dconf.enable = true;
  }

  {
    # Overlay order matters: `self.overlays.default` now registers
    # `secretspec` from upstream nixpkgs-secretspec (0.17.0) — the fork
    # packages (pkgs/secretspec, pkgs/secretspec-provider-sops) are removed.
    # Audit F-13 (2026-07-28): `inputs.niri.overlays.niri` moved to
    # modules/desktop/desktop-modules.nix (zephyr-only).
    nixpkgs.overlays = [
      inputs.llm-agents.overlays.shared-nixpkgs
      self.overlays.default
      inputs.lsfg-vk-nix.overlays.default
    ];
  }
]

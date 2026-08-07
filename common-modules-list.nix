{
  inputs,
  self,
}: [
  # Audit F-13 (2026-07-28): AAGL moved to
  # modules/desktop/desktop-modules.nix (loaded via
  # flake.nix `hosts.zephyr.extraModules` only).
  inputs.nur.modules.nixos.default
  inputs.sops-nix.nixosModules.default
  ./modules/system/sops-secrets-registry.nix
  # hermes-agent NixOS module REMOVED (issue #334) — Hermes is provided by the
  # user nix profile, not nixos-config. See flake.nix for the dropped input.

  inputs.mcp-registry.nixosModules.default

  inputs.caddy-ingress.nixosModules.caddy
  inputs.caddy-ingress.nixosModules.caddy-common

  # ai-gateway NixOS module REMOVED (2026-08-02): the NixOS-side
  # services.ai-inference gateway pulled the torch/sentence-transformers
  # stack into every host closure (multi-hour ROCm builds, sentry build
  # failure). The gateway runs in K8s from a prebuilt image
  # (nexus:5000/ai-inference-gateway, see kubernetes/modules/ai-inference.nix).
  # Mining backend is selected per host via hosts/*/peakminer.nix.
  inputs.gpu-proxy.nixosModules.default

  # Audit F-13 (2026-07-28): Stylix is theme infrastructure, not
  # desktop-only — ALL hosts with home-manager need the stylix NixOS
  # module so that `homeManagerIntegration.followSystem` propagates
  # the stylix HM module (stylix.targets.* options) into the common
  # home-manager config in modules/system/home-manager.nix.
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
  ./modules/system/chronyd.nix

  ./modules/default.nix

  {
    # D-Bus configuration system (required by Stylix / HM dconf activation)
    programs.dconf.enable = true;
  }

  {
    # Overlay order matters: `self.overlays.default` registers bugfixes,
    # system, python, images, hardware, and app overlays from
    # `overlays/default.nix`. The secretspec sops provider is built from
    # upstream `pkgs/secretspec` (0.18.0) and wired through
    # `services.secretspec-validator`; the reverb256 fork was removed
    # 2026-08-07.
    # Audit F-13 (2026-07-28): `inputs.niri.overlays.niri` moved to
    # modules/desktop/desktop-modules.nix (zephyr-only).
    nixpkgs.overlays = [
      inputs.llm-agents.overlays.shared-nixpkgs
      self.overlays.default
      inputs.lsfg-vk-nix.overlays.default
    ];
  }
]

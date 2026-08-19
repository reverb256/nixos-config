{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.desktop.niri-hdr-samsung;
  inherit (lib) mkEnableOption mkIf;
in {
  options.desktop.niri-hdr-samsung = {
    enable = mkEnableOption "NVIDIA tuning + Samsung TV HDR config for niri";
  };

  # The live niri configuration (Samsung TV HDR output + NVIDIA presentation
  # debug flags) is rendered by the standalone home-manager-config flake:
  # modules/niri-config.nix + modules/niri-outputs.nix write
  # ~/.config/niri/config.kdl. In this 3-layer setup the NixOS-level
  # programs.niri module does NOT emit that per-user file, so any NixOS-side
  # programs.niri.settings assignment is orphaned (evaluated, never rendered).
  # The single source of truth lives in home-manager-config.
  #
  # Fork schema (DOCUMENTATION ONLY — do not re-add as NixOS settings):
  #   output "Samsung Electric Company SAMSUNG 0x01000E00" {
  #       max-bpc 10
  #       hdr mode="on" {
  #           reference-luminance 300   # value applied by niri-outputs.nix
  #       }
  #   }
  # Reference: home-manager-config/modules/niri-outputs.nix (zephyr raw KDL append).
  config = mkIf cfg.enable {
    # NVIDIA application profile to fix VRAM leak in niri. This is the only
    # live, non-duplicated setting this module owns.
    hardware.nvidia-niri-profile.enable = true;
  };
}

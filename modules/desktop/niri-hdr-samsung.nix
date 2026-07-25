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

  # Declare programs.niri.settings as a free-form attrset option.
  # The pinned nixpkgs version (9ae611a4) doesn't include programs.niri.settings
  # as a declared sub-option; home-manager's niri config provides it via
  # the sodiboo/niri-flake homeModules, but the NixOS-level module doesn't.
  # Declaring it here avoids evaluation failure while keeping the options
  # available for runtime niri config generation.
  options.programs.niri.settings = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    default = {};
    description = "Niri compositor settings (declared locally for niri-hdr-samsung)";
  };

  config = mkIf cfg.enable {
    # Extend niri settings with NVIDIA tuning and Samsung TV HDR output
    programs.niri.settings = {
      # NVIDIA-specific debug flags
      debug = {
        # NVIDIA DRM presentation timestamps unreliable; use fixed schedule.
        emulate-zero-presentation-time = true;
        # Mitigate swapchain present overhead on NVIDIA.
        wait-for-frame-completion-before-queueing = true;
      };

      # Samsung TV HDR output config (HDMI-A-2)
      # Uses the HDR fork's hdr { } block for full HDR metadata signalling.
      # reference-luminance: SDR white level in nits
      #   203 = Samsung QD-OLED/QN90A typical
      #   150 = darker SDR content (less aggressive tone mapping)
      #   250 = brighter (might clip highlights)
      outputs = {
        "HDMI-A-2" = {
          bpc = 10;
          hdr = {
            enabled = true;
            reference-luminance = 203;
          };
        };
      };
    };

    # NVIDIA application profile to fix VRAM leak in niri
    hardware.nvidia-niri-profile.enable = true;
  };
}

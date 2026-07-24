# Brightness control via wlr-gamma-control-v1 (works on NVIDIA + niri)
# Uses gammastep to scale gamma ramps via the Wayland protocol.
# No GPU patches, no Samsung API, no DDC/CI needed.
# Requires: niri supports wlr-gamma-control-v1 (PR #240, merged in 25.05+)
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.desktop.samsung-tv-brightness;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.desktop.samsung-tv-brightness = {
    enable = mkEnableOption "Gamma-based brightness control via wlr-gamma-control-v1";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      gammastep
      (writeShellScriptBin "samsung-brightness" ''
        set -euo pipefail
        PERCENT=$1
        if [ -z "$PERCENT" ]; then
          echo "Usage: samsung-brightness <0-100>" >&2
          exit 1
        fi
        # Kill any running gammastep
        pkill gammastep 2>/dev/null || true
        # Convert 0-100 to 0.0-1.0
        BRIGHTNESS=$(awk "BEGIN {printf \"%.2f\", $PERCENT / 100}")
        echo "Setting brightness to $PERCENT% ($BRIGHTNESS)"
        exec gammastep -m wayland -b "$BRIGHTNESS" -O 6500
      '')
    ];
  };
}

# Fake backlight bridge — gamma-based brightness via wlr-gamma-control-v1
#
# Creates a virtual /sys/class/backlight-compatible interface using systemd
# path units. When Noctalia (or any brightness tool) writes a value to
# /var/run/fake-backlight/brightness, this runs gammastep -m wayland to
# set the gamma ramp, which works on ALL displays including HDMI TVs that
# lack DDC/CI or kernel backlight support.
#
# Requires: niri (any version with wlr-gamma-control-v1, PR #240+)
# Requires: gammastep (added to systemPackages)
{ config, lib, pkgs, ... }: let
  cfg = config.services.fake-backlight-bridge;
  inherit (lib) mkEnableOption mkOption types mkIf;
  runDir = "/var/run/fake-backlight";
in {
  options.services.fake-backlight-bridge = {
    enable = mkEnableOption "Fake backlight bridge (gamma-based brightness for HDMI/DP monitors without DDC/CI)";
    maxBrightness = mkOption {
      type = types.int;
      default = 100;
      description = "Maximum brightness value (scales to 0.0-1.0 for gammastep)";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ pkgs.gammastep ];

    systemd.services.fake-backlight-apply = {
      description = "Apply fake backlight brightness via gamma ramp";
      after = [ "fake-backlight-setup.service" ];
      wants = [ "fake-backlight-setup.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "apply-brightness" ''
          set -euo pipefail
          BRIGHTNESS_FILE="${runDir}/brightness"
          MAX_BRIGHTNESS="${toString cfg.maxBrightness}"
          if [ -f "$BRIGHTNESS_FILE" ]; then
            VAL=$(cat "$BRIGHTNESS_FILE" 2>/dev/null || echo "$MAX_BRIGHTNESS")
            if [ "$VAL" -gt "$MAX_BRIGHTNESS" ] 2>/dev/null; then VAL=$MAX_BRIGHTNESS; fi
            if [ "$VAL" -lt 0 ] 2>/dev/null; then VAL=0; fi
            BRIGHTNESS=$(awk "BEGIN {printf \"%.2f\", $VAL / $MAX_BRIGHTNESS}")
            pkill gammastep 2>/dev/null || true
            gammastep -m wayland -b "$BRIGHTNESS" -O 6500 &
          fi
        '';
        User = "j_kro";
        Group = "users";
      };
    };

    systemd.services.fake-backlight-setup = {
      description = "Setup fake backlight device for gamma-brightness bridge";
      before = [ "fake-backlight-apply.service" ];
      requiredBy = [ "fake-backlight-apply.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "setup-fake-backlight" ''
          mkdir -p "${runDir}"
          echo "${toString cfg.maxBrightness}" > "${runDir}/max_brightness"
          echo "100" > "${runDir}/brightness"
          chmod 644 "${runDir}/brightness" "${runDir}/max_brightness"
          chown -R j_kro:users "${runDir}"
        '';
      };
    };

    systemd.paths.fake-backlight-watcher = {
      description = "Watch for fake backlight brightness changes";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathModified = "${runDir}/brightness";
        Unit = "fake-backlight-apply.service";
      };
    };
  };
}
NIX
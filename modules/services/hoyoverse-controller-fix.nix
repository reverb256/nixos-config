{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hoyoverse-controller-fix;
in {
  options.services.hoyoverse-controller-fix = {
    enable = lib.mkEnableOption "Apply DualSense/DualShock controller fix for HoYo games";
    wineRunner = lib.mkOption {
      type = lib.types.str;
      default = "/data/@games/hoyoverse/runners/spritz-wine-cachyos-wow64-10.0-7";
      description = "Path to Wine runner";
    };
    prefix = lib.mkOption {
      type = lib.types.str;
      default = "/data/@games/hoyoverse/prefix";
      description = "Path to Wine prefix";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.hoyoverse-controller-fix = {
      description = "Apply DualSense/DualShock controller fix for HoYo games";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "hoyoverse-controller-fix" ''
          set -e
          export WINEPREFIX="${cfg.prefix}"

          # Enable hidraw for DualSense (PS5) and DualShock 4 (PS4) controllers
          ${cfg.wineRunner}/bin/wine reg add \
            'HKLM\System\CurrentControlSet\Services\winebus' \
            /v DisableHidraw /t REG_DWORD /d 0 /f 2>/dev/null || true

          # Also set the emulator to autoload for better compatibility
          ${cfg.wineRunner}/bin/wine reg add \
            'HKLM\System\CurrentControlSet\Services\winebus' \
            /v ImmersiveDevice /t REG_DWORD /d 1 /f 2>/dev/null || true

          # Restart the wine prefix to apply changes
          ${cfg.wineRunner}/bin/wine wineboot -r 2>/dev/null || true
        '';
      };
      wantedBy = ["graphical-session.target"];
    };
  };
}

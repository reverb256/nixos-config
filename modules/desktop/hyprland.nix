{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.programs.hyprland.enable;
in
{
  config = {
    programs.hyprland = {
      enable = lib.mkDefault false;
      withUWSM = true;
    };

    programs.hyprlock.enable = cfg;

    environment.systemPackages = lib.mkIf cfg (
      with pkgs;
      [
        hyprpicker
        hyprcursor
        hyprlock
        hyprsunset
        hyprpolkitagent

        wayvnc
      ]
    );


    environment.etc."uwsm/env-hyprland" = lib.mkIf cfg {
      text = ''
        WLR_DRM_DEVICES=/dev/dri/card2
      '';
    };


    systemd.user.services = lib.mkIf cfg {
      hyprpolkitagent = {
        overrideStrategy = "asDropin";
        serviceConfig = {
          ExecCondition = "${pkgs.systemd}/lib/systemd/systemd-xdg-autostart-condition Hyprland ''";
        };
        enable = true;
      };
    };
  };
}

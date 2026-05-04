{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.programs.hyprland.enable;
in {
  config = {
    programs.hyprland = {
      enable = lib.mkDefault false;
      withUWSM = true;
    };

    programs.hyprlock.enable = cfg;

    xdg.portal = lib.mkIf cfg {
      enable = lib.mkDefault true;
      xdgOpenUsePortal = lib.mkForce false;
      config.hyprland = {
        default = ["hyprland" "gtk"];
        "org.freedesktop.impl.portal.Access" = "gtk";
        "org.freedesktop.impl.portal.FileChooser" = "gtk";
        "org.freedesktop.impl.portal.Notification" = "gtk";
        "org.freedesktop.impl.portal.Secret" = "gnome-keyring";
      };
      extraPortals = lib.mkDefault [
        pkgs.xdg-desktop-portal-hyprland
        pkgs.xdg-desktop-portal-gtk
      ];
    };

    environment.systemPackages = lib.mkIf cfg (
      with pkgs; [
        hyprpicker
        hyprcursor
        hyprlock
        hyprsunset
        hyprpolkitagent

        wayvnc
        xwayland-satellite
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
      xdg-desktop-portal = {
        after = ["xdg-desktop-autostart.target"];
      };
      xdg-desktop-portal-hyprland = {
        after = ["xdg-desktop-autostart.target"];
      };
      xdg-desktop-portal-gtk = {
        after = ["xdg-desktop-autostart.target"];
      };
    };
  };
}

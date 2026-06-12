{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.flatpak-kde;
in {
  options.services.flatpak-kde = {
    enable = mkEnableOption "Flatpak support with Discover and Flathub";

    autoUpdate = mkOption {
      type = types.bool;
      default = true;
      description = "Enable automatic Flatpak updates";
    };

    extraRemotes = mkOption {
      type = types.listOf types.attrs;
      default = [];
      description = "Extra Flatpak remotes to add";
      example = literalExpression ''
        [
          {
            name = "flathub-beta";
            location = "https://flathub.org/beta-repo/flathub-beta.flatpakrepo";
          }
        ]
      '';
    };
  };

  config = mkIf cfg.enable {
    services.flatpak.enable = true;

    environment.systemPackages = with pkgs; [
      flatpak

      kdePackages.discover

      xdg-desktop-portal
      xdg-desktop-portal-gtk
    ];

    xdg.portal = {
      enable = lib.mkDefault true;
      xdgOpenUsePortal = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
      ];
    };

    system.activationScripts.flatpak-setup = ''
      echo "Setting up Flatpak remotes..."
      ${pkgs.flatpak}/bin/flatpak remote-list --system | grep -q flathub || \
        ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists --system flathub https://flathub.org/repo/flathub.flatpakrepo

      ${lib.concatMapStrings (remote: ''
          ${pkgs.flatpak}/bin/flatpak remote-list --system | grep -q ${remote.name} || \
            ${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists --system ${remote.name} ${remote.location}
        '')
        cfg.extraRemotes}
    '';

    environment.etc."polkit-1/rules.d/org.flathub.flatpak.rules".text = ''
      // Allow users to manage Flatpak installations without password
      polkit.addRule(function(action, subject) {
        if ((action.id == "org.freedesktop.flatpak.system-helper" ||
             action.id == "org.freedesktop.flatpak.auth-helper") &&
            subject.isInGroup("wheel")) {
          return polkit.Result.YES;
        }
      });
    '';

    systemd.timers.flatpak-update = mkIf cfg.autoUpdate {
      description = "Flatpak update timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
        Unit = "flatpak-update.service";
      };
    };

    systemd.services.flatpak-update = mkIf cfg.autoUpdate {
      description = "Update Flatpak packages";
      after = ["network-online.target" "spotx-patch.service"];
      wants = ["network-online.target" "spotx-patch.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe pkgs.flatpak + " update --assumeyes";
        User = "root";
      };
    };
  };
}

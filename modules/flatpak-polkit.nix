{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  imports = [./modules];

  options = {
    services.flatpak.polkit = {
      enable = mkEnableOption "Enable custom Flatpak polkit policies";

      allowAppstreamOperations = mkOption {
        type = types.bool;
        default = true;
        description = "Allow regular users to perform AppStream operations without authentication";
      };

      allowSystemOperations = mkOption {
        type = types.bool;
        default = false;
        description = "Allow regular users to perform system-wide operations without authentication";
      };

      allowUserOperations = mkOption {
        type = types.bool;
        default = true;
        description = "Allow regular users to perform user operations without authentication";
      };
    };
  };

  config = mkIf config.services.flatpak.polkit.enable {
    security.polkit.extraConfig = let
      alwaysAllow = ''
        polkit.addRule(function(action, subject) {
          if (action.id == "org.freedesktop.Flatpak.appstream-update" ||
              action.id == "org.freedesktop.Flatpak.metadata-update") {
            return polkit.Result.YES;
          }
        });
      '';

      allowSystemOperations = ''
        polkit.addRule(function(action, subject) {
          if (action.id == "org.freedesktop.Flatpak.app-install" ||
              action.id == "org.freedesktop.Flatpak.runtime-install" ||
              action.id == "org.freedesktop.Flatpak.app-uninstall" ||
              action.id == "org.freedesktop.Flatpak.runtime-uninstall" ||
              action.id == "org.freedesktop.Flatpak.install-bundle" ||
              action.id == "org.freedesktop.Flatpak.configure" ||
              action.id == "org.freedesktop.Flatpak.configure-remote" ||
              action.id == "org.freedesktop.Flatpak.modify-repo") {
            return polkit.Result.YES;
          }
        });
      '';

      allowUserOperations = ''
        polkit.addRule(function(action, subject) {
          if (action.id == "org.freedesktop.Flatpak.app-update" ||
              action.id == "org.freedesktop.Flatpak.runtime-update" ||
              action.id == "org.freedesktop.Flatpak.update-remote") {
            return polkit.Result.YES;
          }
        });
      '';

      rules = concatStringsSep "\n" [
        (mkIf config.services.flatpak.polkit.allowAppstreamOperations alwaysAllow)
        (mkIf config.services.flatpak.polkit.allowSystemOperations allowSystemOperations)
        (mkIf config.services.flatpak.polkit.allowUserOperations allowUserOperations)
      ];
    in
      rules;
  };
}

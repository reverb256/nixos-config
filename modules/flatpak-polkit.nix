{
  config,
  lib,
  ...
}:
with lib; {
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
        description = "Allow j_kro user to perform system-wide Flatpak operations without authentication";
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
              action.id == "org.freedesktop.Flatpak.install-bundle" ||
              action.id == "org.freedesktop.Flatpak.configure" ||
              action.id == "org.freedesktop.Flatpak.configure-remote" ||
              action.id == "org.freedesktop.Flatpak.modify-repo") {
            // j_kro has full sysadmin privileges for Flatpak system operations
            if (subject.user == "j_kro") {
              return polkit.Result.YES;
            }
          } else if (action.id == "org.freedesktop.Flatpak.app-uninstall" ||
                     action.id == "org.freedesktop.Flatpak.runtime-uninstall") {
            // j_kro can uninstall system packages
            if (subject.user == "j_kro") {
              return polkit.Result.YES;
            }
          }
        });
      '';

      allowUserOperations = ''
        polkit.addRule(function(action, subject) {
          if (action.id == "org.freedesktop.Flatpak.app-update" ||
              action.id == "org.freedesktop.Flatpak.runtime-update" ||
              action.id == "org.freedesktop.Flatpak.update-remote") {
            // j_kro can update all Flatpak packages without authentication
            // This enables automatic updates for the sysadmin user
            if (subject.user == "j_kro") {
              return polkit.Result.YES;
            }
          } else if (action.id == "org.freedesktop.Flatpak.app-uninstall" ||
                     action.id == "org.freedesktop.Flatpak.runtime-uninstall") {
             # j_kro can uninstall user packages without authentication
            if (action.lookup("installation") == "user" && subject.user == "j_kro") {
              return polkit.Result.YES;
            }
          }
        });
      '';

      rules = concatStringsSep "\n" (lib.filter (x: x != "") [
        (optionalString config.services.flatpak.polkit.allowAppstreamOperations alwaysAllow)
        (optionalString config.services.flatpak.polkit.allowSystemOperations allowSystemOperations)
        (optionalString config.services.flatpak.polkit.allowUserOperations allowUserOperations)
      ]);
    in
      rules;
  };
}

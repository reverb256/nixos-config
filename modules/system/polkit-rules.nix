# PolKit rules for NixOS
# Disable password prompts for systemd service management
{
  config,
  lib,
  ...
}: let
  cfg = config.security.polkit;
in {
  options.security.polkit = {
    extraConfig = lib.mkAfter ''
      # Allow wheel group to manage systemd services without authentication
      # This prevents password prompts when using systemctl commands
      polkit.addRule(function(action, subject) {
        if (
          action.id == "org.freedesktop.systemd1.manage-units" &&
          subject.isInGroup("wheel")
        ) {
          return polkit.Result.YES;
        }
      });

      # Also allow managing user services without authentication
      polkit.addRule(function(action, subject) {
        if (
          action.id == "org.freedesktop.systemd1.manage-units" &&
          subject.user == "j_kro"
        ) {
          return polkit.Result.YES;
        }
      });
    '';
  };
}

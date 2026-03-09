# PolKit rules for NixOS
# Disable password prompts for systemd service management
{...}: {
  # Add polkit extra rules for systemd service management
  security.polkit.extraConfig = ''
    // Allow wheel group to manage systemd services without authentication
    // This prevents password prompts when using systemctl commands
    polkit.addAdminRule(function(action, subject) {
      return ["unix-group:wheel"];
    });

    polkit.addRule(function(action, subject) {
      if (
        action.id == "org.freedesktop.systemd1.manage-units" &&
        subject.isInGroup("wheel")
      ) {
        return polkit.Result.YES;
      }
    });

    // Also allow managing user services without authentication
    polkit.addRule(function(action, subject) {
      if (
        action.id == "org.freedesktop.systemd1.manage-units" &&
        subject.user == "j_kro"
      ) {
        return polkit.Result.YES;
      }
    });
  '';
}

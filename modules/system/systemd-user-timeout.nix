# Systemd User Manager Timeout Configuration
# Fixes nixos-rebuild switch hang at "reloading user units"
{
  config,
  lib,
  ...
}: let
    inherit (lib) mkEnableOption mkIf types;
  cfg = config.services.systemd-user-timeout;
in {
  options.services.systemd-user-timeout = {
    enable = mkEnableOption "Fix systemd user unit reload timeout";
  };

  config = mkIf cfg.enable {
    # Increase systemd user manager timeout for reload operations
    # This fixes nixos-rebuild switch hanging at "reloading user units"
    systemd.user.extraConfig = ''
      # Increase timeout for user service reload operations
      # Default is 90s, but some services (like KDE components) can take longer
      DefaultTimeoutStartSec=180s
      DefaultTimeoutStopSec=180s
    '';
  };
}

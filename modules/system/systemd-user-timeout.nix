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
    systemd.user.extraConfig = ''
      DefaultTimeoutStartSec=180s
      DefaultTimeoutStopSec=180s
    '';
  };
}

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
    # Increase systemd user manager timeout for reload operations.
    # This fixes nixos-rebuild switch hanging at "reloading user units".
    # NOTE (2026-07-21, issue #300): `systemd.user.extraConfig` was removed
    # from upstream NixOS — modern equivalent is
    # `systemd.user.settings.Manager`. Migrated here so the assertion
    # "systemd.user.extraConfig no longer has any effect" no longer fires.
    systemd.user.settings.Manager = {
      DefaultTimeoutStartSec = "180s";
      DefaultTimeoutStopSec  = "180s";
    };
  };
}

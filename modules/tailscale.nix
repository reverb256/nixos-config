# Tailscale - Secure mesh VPN
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; {
  services.tailscale = {
    enable = true;
  };

  # Tailscale logging
  systemd.services.tailscaled = {
    environment = {
      TS_LOG_LEVEL = "info";
    };
  };
}

# Tailscale - Secure mesh VPN
{lib, ...}:
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

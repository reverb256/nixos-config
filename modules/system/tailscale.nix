{lib, ...}:
with lib; {
  services.tailscale = {
    enable = true;
  };

  systemd.services.tailscaled = {
    environment = {
      TS_LOG_LEVEL = "info";
    };
  };
}

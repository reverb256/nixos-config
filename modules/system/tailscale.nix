{lib, ...}:
with lib; {
  services.tailscale = {
    enable = lib.mkDefault true;
    openFirewall = true;
    extraSetFlags = [
      "--ssh"
      "--accept-dns=false"
    ];
    extraUpFlags = [
      "--reset"
    ];
  };

  systemd.services.tailscaled = {
    environment = {
      TS_LOG_LEVEL = "info";
    };
  };
}

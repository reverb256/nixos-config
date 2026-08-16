{lib, ...}:
with lib; {
  services.tailscale = {
    enable = lib.mkDefault true;
    openFirewall = true;
    extraSetFlags = [
      "--ssh"
      # --accept-dns=false REMOVED 2026-08-16: MagicDNS now enabled.
      # Prerequisite: tailscaled orders after network-online.target (see
      # systemd.services.tailscaled below) so it never claims DNS before
      # connectivity exists (nixpkgs #527403).
    ];
    extraUpFlags = [
      "--reset"
    ];
  };

  systemd.services.tailscaled = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    environment = {
      TS_LOG_LEVEL = "info";
    };
  };
}

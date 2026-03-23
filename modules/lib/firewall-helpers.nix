# Firewall configuration helper functions
# Simplifies common firewall rule patterns
{
  lib,
  pkgs,
  ...
}: rec {
  /*
  Open TCP ports for a service (preserves existing ports)

  # Example
  mkTCPPorts [80 443]  # Opens ports 80 and 443
  */
  mkTCPPorts = ports: {
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault ports;
  };

  /*
  Open UDP ports for a service (preserves existing ports)

  # Example
  mkUDPPorts [53 8472]  # Opens ports 53 and 8472
  */
  mkUDPPorts = ports: {
    networking.firewall.allowedUDPPorts = lib.mkOptionDefault ports;
  };

  /*
  Open both TCP and UDP ports for a service

  # Example
  mkPorts {
    tcp = [80 443];
    udp = [53];
  }
  */
  mkPorts = {
    tcp ? [],
    udp ? [],
  }:
    lib.mkMerge [
      (lib.optionalAttrs (tcp != []) {networking.firewall.allowedTCPPorts = lib.mkOptionDefault tcp;})
      (lib.optionalAttrs (udp != []) {networking.firewall.allowedUDPPorts = lib.mkOptionDefault udp;})
    ];

  /*
  Open ports only on a specific interface (e.g., Tailscale VPN)

  # Example
  mkInterfaceTCPPorts "tailscale0" [9100]  # Port 9100 on tailscale0 only
  */
  mkInterfaceTCPPorts = interface: ports: {
    networking.firewall.interfaces.${interface}.allowedTCPPorts = ports;
  };

  /*
  Common port constants from network-constants.nix
  Use these instead of hardcoding port numbers
  */
  ports =
    config.networking.cluster.ports or {
      # Monitoring stack
      monitoring = [9100 9101 9113]; # node-exporter, prometheus, grafana

      # Mining
      mining = [3333 42069 42070]; # various mining ports

      # AI/Inference
      ai = [8080 6333]; # gateway, qdrant

      # Web services
      web = [80 443]; # HTTP/HTTPS

      # File sharing
      fileSharing = [22000 21027]; # syncthing
    };
}

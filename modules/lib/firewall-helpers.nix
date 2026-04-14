{
  lib,
  config,
  ...
}: rec {
  /*
  Open TCP ports for a service (preserves existing ports)

  mkTCPPorts [80 443]
  */
  mkTCPPorts = ports: {
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault ports;
  };

  /*
  Open UDP ports for a service (preserves existing ports)

  mkUDPPorts [53 8472]
  */
  mkUDPPorts = ports: {
    networking.firewall.allowedUDPPorts = lib.mkOptionDefault ports;
  };

  /*
  Open both TCP and UDP ports for a service

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

  mkInterfaceTCPPorts "tailscale0" [9100]
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
      monitoring = [9100 9101 9113];

      mining = [3333 42069 42070];

      ai = [8080 6333];

      web = [80 443];

      fileSharing = [22000 21027];
    };
}

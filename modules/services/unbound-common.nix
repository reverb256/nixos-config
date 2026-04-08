# Unified Unbound DNS Configuration for All Cluster Hosts
# Simple configuration using standard NixOS unbound module
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf mkOption types;
  cfg = config.clusterNetworking;
in
{
  options.services.unbound-common = {
    enable = lib.mkEnableOption "Unbound DNS resolver with DNS-over-TLS (cluster-wide config)";
  };

  config = mkIf cfg.enable {
    services.unbound = {
      enable = true;

      settings = {
        server = {
          interface = [
            "127.0.0.1"
            cfg.ipAddress
          ];
          access-control = [
            "127.0.0.0/8 allow"
            "10.1.1.0/24 allow"
            "10.244.0.0/16 allow"
          ];
          num-threads = 4;
          msg-cache-size = "128m";
          rrset-cache-size = "128m";
          hide-identity = true;
          hide-version = true;
          # Include file with local DNS records (cluster services)
          include = "/etc/unbound/local-dns.conf";
        };

        forward-zone = [
          {
            name = ".";
            forward-addr = [
              "1.1.1.1"
              "1.0.0.1"
              "8.8.8.8"
              "8.8.4.4"
            ];
          }
        ];
      };
    };

    # Local DNS records for cluster services
    # All point to the keepalived VIP (10.1.1.100) which floats between
    # zephyr (MASTER) and nexus (BACKUP). Caddy on zephyr reverse-proxies
    # to nexus:30080 (K8s Caddy ingress NodePort).
    #
    # Using an include file because the NixOS unbound module's RFC42
    # format generator joins list values with spaces, breaking
    # local-data records that contain spaces.
    environment.etc."unbound/local-dns.conf".text =
      lib.concatMapStrings (record: "local-data: \"${record}\"\n")
        [
          # K8s ingress hosts
          "search.lan. IN A 10.1.1.100"
          "ai.lan. IN A 10.1.1.100"
          "openwebui.lan. IN A 10.1.1.100"
          # .cluster.local aliases
          "search.cluster.local. IN A 10.1.1.100"
          "ai.cluster.local. IN A 10.1.1.100"
          "openwebui.cluster.local. IN A 10.1.1.100"
        ];

    networking.firewall.allowedUDPPorts = lib.mkOptionDefault [ 53 ];
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ 53 ];
  };
}

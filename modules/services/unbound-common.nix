# Unified Unbound DNS Configuration for All Cluster Hosts
# Each host imports this module to get DNS-over-TLS to Cloudflare, Google, Quad9
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkIf mkOption types;
  cfg = config.clusterNetworking;
in {
  options.services.unbound-common = {
    enable = lib.mkEnableOption "Unbound DNS resolver with DNS-over-TLS (cluster-wide config)";
  };

  config = mkIf cfg.enable {
    services.unbound = {
      enable = true;
      settings = {
        server = {
          # Performance tuning
          num-threads = 4;
          msg-cache-size = "128m";
          rrset-cache-size = "128m";
          msg-cache-slabs = 4;
          rrset-cache-slabs = 4;

          # Security
          val-clean-additional = true;
          aggressive-nsec = true;
          hide-identity = true;
          hide-version = true;
          qname-minimisation = true;
          rrset-roundrobin = true;

          # Privacy
          logfile = "/dev/null";
          use-syslog = false;
          log-queries = false;
          log-replies = false;

          # TTL
          cache-max-ttl = 86400;
          cache-min-ttl = 300;

          # EDNS
          edns-buffer-size = 1232;

          # TLS settings for DNS-over-TLS
          tls-cert-bundle = "/etc/ssl/certs/ca-bundle.crt";
          tls-upstream = true;
        };

        # Forward to DNS-over-TLS servers
        forward-zone = [
          {
            name = ".";
            forward-addr = [
              "1.1.1.1@853#cloudflare-dns.com"
              "1.0.0.1@853#cloudflare-dns.com"
              "8.8.8.8@853#dns.google"
              "8.8.4.4@853#dns.google"
              "9.9.9.9@853#dns.quad9.net"
              "149.112.112.112@853#dns.quad9.net"
            ];
          }
        ];
      };
    };

    # CRITICAL: Prevent systemd from killing Unbound during rebuilds
    systemd.services.unbound = {
      restartIfChanged = false;
      reloadIfChanged = false;
      restartTriggers = [ ];  # Empty = never restart due to config changes
      serviceConfig = {
        Restart = "always";
        RestartSec = "10s";
        TimeoutStartSec = "30s";
      };
    };

    # Firewall
    networking.firewall.allowedUDPPorts = lib.mkOptionDefault [ 53 ];
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ 53 ];
  };
}

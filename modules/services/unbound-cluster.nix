# Unbound DNS Module
# Local DNS resolver for cluster with Tailscale integration
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.unbound-cluster;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
in

{
  options.services.unbound-cluster = {
    enable = mkEnableOption "Unbound DNS resolver for local cluster network";

    upstream = mkOption {
      type = types.listOf types.str;
      default = [
        "100.100.100.100" # Tailscale DNS
        "1.1.1.1" # Cloudflare fallback
        "8.8.8.8" # Google fallback
      ];
      description = "Upstream DNS servers";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "10.1.1.110";
      description = "Address to listen on";
    };

    port = mkOption {
      type = types.port;
      default = 53;
      description = "DNS port";
    };
  };

  config = mkIf cfg.enable {
    # Disable systemd-resolved's stub resolver to use unbound directly
    services.resolved.enable = lib.mkForce false;

    services.unbound = {
      enable = true;
      settings = {
        server = {
          # Listen on local IP (not just localhost)
          interface = [
            "127.0.0.1"
            cfg.listenAddress
          ];
          port = cfg.port;

          # Access control - allow local network
          access-control = [
            "127.0.0.0/8 allow"
            "10.1.1.0/24 allow"
            "100.64.0.0/10 allow" # Tailscale
          ];

          # Security hardening
          harden-glue = true;
          harden-dnssec-stripped = true;
          use-caps-for-id = false;
          prefetch = true;
          edns-buffer-size = 1232;

          # Hide info
          hide-identity = true;
          hide-version = true;

          # Performance
          num-threads = 2;

          # Local zone for cluster hostnames
          local-zone = ''"cluster.local" static'';

          # Local data records for cluster hosts
          local-data = [
            ''"zephyr.cluster.local. IN A 10.1.1.110"''
            ''"zephyr IN A 10.1.1.110"''
            ''"nexus.cluster.local. IN A 10.1.1.120"''
            ''"nexus IN A 10.1.1.120"''
            ''"forge.cluster.local. IN A 10.1.1.130"''
            ''"forge IN A 10.1.1.130"''
            ''"sentry.cluster.local. IN A 10.1.1.140"''
            ''"sentry IN A 10.1.1.140"''
          ];
        };

        # Forward all other queries to upstream
        forward-zone = [
          {
            name = ".";
            forward-addr = cfg.upstream;
            forward-tls-upstream = true;
          }
        ];
      };
    };

    # Firewall - allow DNS from local network
    networking.firewall.allowedUDPPorts = [ cfg.port ];
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}

# Unbound DNS Module
# Local DNS resolver for cluster with Tailscale integration
{
  config,
  lib,
  ...
}: let
  cfg = config.services.unbound-cluster;
  inherit
    (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
in {
  options.services.unbound-cluster = {
    enable = mkEnableOption "Unbound DNS resolver for local cluster network";

    upstream = mkOption {
      type = types.listOf types.str;
      default = [
        "100.100.100.100" # Tailscale DNS (non-TLS)
      ];
      description = "Upstream DNS servers (non-TLS)";
    };

    upstreamTls = mkOption {
      type = types.listOf types.str;
      default = [
        "9.9.9.9@853" # Quad9 DNS-over-TLS (security-focused, blocks malicious domains)
        "1.1.1.1@853" # Cloudflare DNS-over-TLS (privacy-focused)
        "8.8.8.8@853" # Google DNS-over-TLS (global reach)
      ];
      description = "Upstream DNS servers with TLS (port 853 for DoT)";
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
          inherit (cfg) port;

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

          # Security - prevent forwarding private network queries to upstream DNS
          # These domains will NEVER be forwarded to external resolvers
          private-domain = [
            ''"cluster.local"''
            ''"10.in-addr.arpa"''
            ''"168.192.in-addr.arpa"''
            ''"16.172.in-addr.arpa"''
            ''"tigris-ule.ts.net"'' # Tailscale domain
          ];

          # Local zones - never forward these to upstream DNS
          # Cluster hostname zone
          local-zone = [
            ''"cluster.local" static''
            # Private network zones (RFC 1918) - prevent leaking local network queries
            ''"10.in-addr.arpa" static'' # 10.0.0.0/8 reverse DNS
            ''"168.192.in-addr.arpa" static'' # 192.168.0.0/16 reverse DNS
            ''"16.172.in-addr.arpa" static'' # 172.16.0.0/12 reverse DNS
            # Tailscale network zone (CGNAT)
            ''"tigris-ule.ts.net" static''
          ];

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

        # Forward zone - mix of TLS and non-TLS upstreams
        # Unbound automatically uses TLS for @853 ports, plain DNS for others
        forward-zone = [
          {
            name = ".";
            forward-addr = cfg.upstream ++ cfg.upstreamTls;
            forward-tls-upstream = true;
          }
        ];
      };
    };

    # Firewall - allow DNS from local network
    networking.firewall.allowedUDPPorts = [cfg.port];
    networking.firewall.allowedTCPPorts = [cfg.port];
  };
}

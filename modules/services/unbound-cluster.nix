# Unbound DNS Module
# Local DNS resolver for cluster with Tailscale integration
{
  config,
  pkgs,
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
          # Controls which CLIENTS can query this DNS server (not domain blocking)
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
            # cluster.local forwarded to Kubernetes DNS (see forward-zone below)
            ''"10.in-addr.arpa"''
            ''"168.192.in-addr.arpa"''
            ''"16.172.in-addr.arpa"''
            # Note: tigris-ule.ts.net handled by forward-zone to Tailscale DNS
          ];

          # Local zones - never forward these to upstream DNS
          # Note: cluster.local is NOT in local-zone - forwarded to Kubernetes DNS
          local-zone = [
            # cluster.local handled by forward-zone to Kubernetes DNS (see forward-zone below)
            ''"lan" static'' # Local network .lan domain
            # Private network zones (RFC 1918) - prevent leaking local network queries
            ''"10.in-addr.arpa" static'' # 10.0.0.0/8 reverse DNS
            ''"168.192.in-addr.arpa" static'' # 192.168.0.0/16 reverse DNS
            ''"16.172.in-addr.arpa" static'' # 172.16.0.0/12 reverse DNS
            # ================================================================================
            # SECURITY: Analytics & Telemetry Blocklist (DNS-level blocking)
            # ================================================================================
            # Blocks VRChat, Unity, and related analytics/telemetry for privacy
            # Using "refuse" action returns REFUSED response (not NXDOMAIN)
            # This prevents the application from falling back to other DNS servers
            # Source: https://github.com/louisa-uno/VRChatAnalyticsBlocklist
            # VRChat/Amplitude Analytics
            ''"api.amplitude.com" refuse''
            ''"api2.amplitude.com" refuse''
            ''"api.lab.amplitude.com" refuse''
            ''"api.eu.amplitude.com" refuse''
            ''"regionconfig.amplitude.com" refuse''
            ''"regionconfig.eu.amplitude.com" refuse''
            ''"api3.amplitude.com" refuse''
            ''"cdn.amplitude.com" refuse''
            ''"info.amplitude.com" refuse''
            ''"static.amplitude.com" refuse''
            # Unity Analytics
            ''"api.uca.cloud.unity3d.com" refuse''
            ''"config.uca.cloud.unity3d.com" refuse''
            ''"perf-events.cloud.unity3d.com" refuse''
            ''"public.cloud.unity3d.com" refuse''
            ''"cdp.cloud.unity3d.com" refuse''
            ''"data-optout-service.uca.cloud.unity3d.com" refuse''
            ''"ecommerce.iap.unity.com" refuse''
            # Note: tigris-ule.ts.net handled by forward-zone to Tailscale DNS
          ];

          # Local data records for cluster hosts
          local-data = [
            # Kubernetes API server
            ''"kubernetes.default.svc.cluster.local. IN A 10.0.0.10"''

            # Cluster hosts (cluster.local domain)
            ''"zephyr.cluster.local. IN A 10.1.1.110"''
            ''"zephyr IN A 10.1.1.110"''
            ''"nexus.cluster.local. IN A 10.1.1.120"''
            ''"nexus IN A 10.1.1.120"''
            ''"forge.cluster.local. IN A 10.1.1.130"''
            ''"forge IN A 10.1.1.130"''
            ''"sentry.cluster.local. IN A 10.1.1.140"''
            ''"sentry IN A 10.1.1.140"''

            # Cluster hosts (.lan domain for convenience)
            ''"zephyr.lan. IN A 10.1.1.110"''
            ''"nexus.lan. IN A 10.1.1.120"''
            ''"forge.lan. IN A 10.1.1.130"''
            ''"sentry.lan. IN A 10.1.1.140"''

            # ================================================================================
            # FRIENDLY SERVICE NAMES - Wildcard for *.cluster.local → Caddy Ingress
            # ================================================================================
            # All *.cluster.local queries will fall through to Caddy ingress
            # Caddy then routes to the appropriate backend service

            # Kubernetes Caddy Ingress (primary ingress for cluster.local)
            ''"*.cluster.local. IN CNAME caddy-ingress.ingress-system.svc.cluster.local."''

            # Kubernetes services (direct access via short names)
            # These are fallbacks if ingress routing is not used
            #
            # ================================================================================
            # REMOVED: Conflicting static A records (2026-03-24)
            # ================================================================================
            # These static A records conflict with the wildcard CNAME for *.cluster.local
            # Wildcard CNAME is authoritative: *.cluster.local → caddy-ingress.ingress-system.svc.cluster.local
            # Commented out (not deleted) for 1-week rollback window
            #
            # AI/ML Services (commented out - use wildcard CNAME)
            # ''"ai.cluster.local. IN A 10.1.1.120"''
            # ''"llm.cluster.local. IN A 10.1.1.120"''
            # ''"rag.cluster.local. IN A 10.1.1.120"''
            #
            # # Home Lab Services (commented out - use wildcard CNAME)
            # ''"home.cluster.local. IN A 10.1.1.110"''
            # ''"vault.cluster.local. IN A 10.1.1.110"''
            # ''"media.cluster.local. IN A 10.1.1.120"''
            #
            # # Development Tools (commented out - use wildcard CNAME)
            # ''"git.cluster.local. IN A 10.1.1.110"''
            # ''"ci.cluster.local. IN A 10.1.1.110"''
            # ''"nix.cluster.local. IN A 10.1.1.110"''
            #
            # # Monitoring (commented out - use wildcard CNAME)
            # ''"metrics.cluster.local. IN A 10.1.1.110"''
            # ''"logs.cluster.local. IN A 10.1.1.110"''
            # ''"dash.cluster.local. IN A 10.1.1.110"''
            #
            # # Utilities (commented out - use wildcard CNAME)
            # ''"search.cluster.local. IN A 10.1.1.100"''
            # ''"chat.cluster.local. IN A 10.1.1.110"''
            # ''"files.cluster.local. IN A 10.1.1.120"''
          ];
        };

        # Forward zone - mix of TLS and non-TLS upstreams
        # Unbound automatically uses TLS for @853 ports, plain DNS for others
        forward-zone = [
          # ========================================================================
          # KUBERNETES DNS FORWARDING - Cluster services
          # ========================================================================
          # Forward all Kubernetes service queries to Kubernetes DNS
          # This enables resolution of: <service>.<namespace>.svc.cluster.local
          {
            name = "svc.cluster.local.";
            forward-addr = ["10.0.0.10"]; # Kubernetes DNS service (kube-dns)
            forward-tls-upstream = false;
          }
          # Forward all Kubernetes pod queries to Kubernetes DNS
          {
            name = "pod.cluster.local.";
            forward-addr = ["10.0.0.10"]; # Kubernetes DNS service (kube-dns)
            forward-tls-upstream = false;
          }
          # Tailscale MagicDNS - forward all .ts.net queries to Tailscale DNS
          {
            name = "ts.net.";
            forward-addr = ["100.100.100.100"];
            forward-tls-upstream = false;
          }
          # Specific tailnet domain
          {
            name = "tigris-ule.ts.net.";
            forward-addr = ["100.100.100.100"];
            forward-tls-upstream = false;
          }
          # Default forward zone for all other queries
          {
            name = ".";
            forward-addr = cfg.upstream ++ cfg.upstreamTls;
            forward-tls-upstream = true;
          }
        ];
      };
    };

    # Firewall - allow DNS from local network
    networking.firewall.allowedUDPPorts = lib.mkOptionDefault [cfg.port];
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [cfg.port];

    # Health monitoring
    systemd.services.unbound-health-check = {
      description = "Monitor Unbound DNS resolution to Kubernetes";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "unbound-health" ''
          #!/bin/sh
          echo "[unbound-health-check] Checking DNS resolution..."

          # Test K8s service resolution (via forward-zone)
          if ! ${pkgs.dnsutils}/bin/dig kubernetes.default.svc.cluster.local @127.0.0.1 | grep -q "NOERROR"; then
            echo "[unbound-health-check] ❌ Kubernetes DNS resolution failed (kubernetes.default.svc.cluster.local)"
            systemctl try-restart unbound
            exit 1
          fi

          # Test local cluster host resolution
          if ! ${pkgs.dnsutils}/bin/dig zephyr.cluster.local @127.0.0.1 | grep -q "NOERROR"; then
            echo "[unbound-health-check] ❌ Local cluster host resolution failed (zephyr.cluster.local)"
            systemctl try-restart unbound
            exit 1
          fi

          # Test external DNS resolution
          if ! ${pkgs.dnsutils}/bin/dig example.com @127.0.0.1 | grep -q "NOERROR"; then
            echo "[unbound-health-check] ❌ External DNS resolution failed (example.com)"
            systemctl try-restart unbound
            exit 1
          fi

          echo "[unbound-health-check] ✅ DNS health check passed"
        '';
        User = "root";
      };
    };

    systemd.timers.unbound-health-check = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/5";  # Every 5 minutes
        Persistent = true;
      };
    };
  };
}

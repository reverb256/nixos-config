# Unified Unbound DNS Configuration for All Cluster Hosts
# Simple configuration using standard NixOS unbound module
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
    # 2026-08-15: local-dns.conf is replaced at activation but unbound was
    # never restarted -> .lan records NXDOMAIN until manual restart (hit on
    # sentry + zephyr). Reload the service when the include file changes.
    systemd.services.unbound.reloadTriggers =
      [ config.environment.etc."unbound/local-dns.conf".source ];

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
    # 2026-08-15: FULL domain set synced from modules/network/cluster-dns.nix
    # (the SSOT). That module is NOT yet imported by any host, so the ACTIVE
    # list must mirror it or .lan services (auth.lan especially) 404 in DNS —
    # which crash-loops central-auth and fails every nexus deploy. SSOT import
    # is the follow-up; keep these two lists in lockstep until then.
    environment.etc."unbound/local-dns.conf".text =
      lib.concatMapStrings (record: "local-data: \"${record}\"\n")
      [
        # K8s ingress hosts
        "search.lan. IN A 10.1.1.100"
        "ai.lan. IN A 10.1.1.100"
        "openwebui.lan. IN A 10.1.1.100"
        # Host-service domains via VIP (Caddy ingress)
        "ai-inference.lan. IN A 10.1.1.100"
        "auth.lan. IN A 10.1.1.100"
        "qdrant.lan. IN A 10.1.1.100"
        "n8n.lan. IN A 10.1.1.100"
        "mission-control.lan. IN A 10.1.1.100"
        "grafana.lan. IN A 10.1.1.100"
        "privacy-filter.lan. IN A 10.1.1.100"
        "workspace.lan. IN A 10.1.1.100"
        "dashboard.lan. IN A 10.1.1.100"
        "maplespike.lan. IN A 10.1.1.100"
        "api.maplespike.lan. IN A 10.1.1.100"
        "mcp.maplespike.lan. IN A 10.1.1.100"
        "auth.maplespike.lan. IN A 10.1.1.100"
        "status.maplespike.lan. IN A 10.1.1.100"
        "uptime.maplespike.lan. IN A 10.1.1.100"
        "haven.lan. IN A 10.1.1.100"
        "dev.maplespike.lan. IN A 10.1.1.100"
        "dev-api.maplespike.lan. IN A 10.1.1.100"
        "dev-mcp.maplespike.lan. IN A 10.1.1.100"
        "gitea.lan. IN A 10.1.1.100"
        # Forge / Sentry / Hermes
        "mining.lan. IN A 10.1.1.130"
        "monitoring.lan. IN A 10.1.1.140"
        "prometheus.lan. IN A 10.1.1.140"
        "alertmanager.lan. IN A 10.1.1.140"
        "hermes.lan. IN A 10.1.1.120"
        "api.hermes.lan. IN A 10.1.1.120"
        # .cluster.local aliases (keep the historical three)
        "search.cluster.local. IN A 10.1.1.100"
        "ai.cluster.local. IN A 10.1.1.100"
        "openwebui.cluster.local. IN A 10.1.1.100"
      ];

    networking.firewall.allowedUDPPorts = lib.mkOptionDefault [53];
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [53];
  };
}

# =============================================================================
# HAProxy Load Balancer for Kubernetes HA
# =============================================================================
#
# Purpose: Layer 4 load balancer for Kubernetes API server
#
# Architecture:
#   - Distributes traffic across 3 API server instances
#   - Health checks with automatic failover
#   - Statistics endpoint for monitoring
#   - Runs on all master nodes
#
# VIP Management:
#   - Keepalived manages VIP (10.1.1.100)
#   - Priority-based failover (Zephyr=110, Nexus=100, Sentry=90)
#   - Active-passive configuration
#
# Usage:
#   services.haproxy-kubernetes = {
#     enable = true;
#     priority = 110;  # Zephyr: 110, Nexus: 100, Sentry: 90
#   };
#
# =============================================================================
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.services.haproxy-kubernetes;

  # HAProxy configuration template
  haproxyConfig = {
    defaults = {
      log = "global";
      mode = "tcp";
      option = ["tcplog" "dontlognull"];
      retries = 3;
      timeout = {
        connect = "10s";
        client = "1m";
        server = "1m";
      };
    };

    global = {
      log = "127.0.0.1 local0";
      chroot = "/var/lib/haproxy";
      stats = {
        socket = "/run/haproxy/admin.sock mode 600 level admin";
        timeout = "30s";
      };
      user = "haproxy";
      group = "haproxy";
      daemon = false; # Managed by systemd
      maxconn = 4000;
    };

    # Statistics endpoint
    "stats stats" = {
      mode = "http";
      bind = "*:8404";
      stats = {
        enable = true;
        hide-version = true;
        uri = "/";
        realm = "HAProxy Statistics";
        auth = "admin:changeme"; # Change this!
      };
    };

    # Kubernetes API frontend (VIP)
    "frontend kubernetes-api" = {
      bind = "${cfg.vip}:6443";
      mode = "tcp";
      option = ["tcplog"];
      defaultBackend = "kubernetes-api-backend";
    };

    # Kubernetes API backend
    "backend kubernetes-api-backend" = {
      mode = "tcp";
      option = ["tcp-check" "tcplog"];
      balance = "roundrobin";
      timeout = {
        connect = "5s";
        server = "5s";
      };
      # Server definitions (added dynamically below)
    };

    # Health check endpoint
    "frontend health" = {
      bind = "*:8080";
      mode = "http";
      "default backend" = "health-backend";
    };

    "backend health-backend" = {
      mode = "http";
      "http-check expect" = "string OK";
    };
  };
  # Generate backend servers from master nodes
in {
  options.services.haproxy-kubernetes = {
    enable = mkEnableOption "HAProxy load balancer for Kubernetes API";

    vip = mkOption {
      type = types.str;
      default = "10.1.1.100";
      description = "Virtual IP for API server";
    };

    interface = mkOption {
      type = types.str;
      default = "eth0";
      description = "Network interface for VIP";
    };

    priority = mkOption {
      type = types.int;
      description = "Keepalived priority (higher = preferred master)";
    };

    masterNodes = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Node name";
          };
          ip = mkOption {
            type = types.str;
            description = "Node IP address";
          };
        };
      });
      default = [
        {
          name = "zephyr";
          ip = "10.1.1.110";
        }
        {
          name = "nexus";
          ip = "10.1.1.120";
        }
        {
          name = "sentry";
          ip = "10.1.1.140";
        }
      ];
      description = "Kubernetes master nodes";
    };

    statsPassword = mkOption {
      type = types.str;
      default = "changeme";
      description = "Password for HAProxy statistics page";
    };
  };

  config = mkIf cfg.enable {
    # ============================================================================
    # SERVICES - HAPROXY, KEEPALIVED, and PROMETHEUS
    # ============================================================================
    services = {
      # ========================================================================
      # HAPROXY PACKAGE and CONFIG
      # ========================================================================
      haproxy = {
        enable = true;

        config = let
          # Convert Nix config to HAProxy format
          mkSection = name: settings:
            concatStringsSep "\n" (
              ["${name}"]
              ++ (mapAttrsToList (
                  k: v:
                    if isList v
                    then "    ${concatStringsSep " " v}"
                    else if isAttrs v
                    then
                      concatStringsSep "\n" (
                        mapAttrsToList (k2: v2: "    ${k2} ${v2}") v
                      )
                    else "    ${k} ${v}"
                )
                settings)
            );

          backendSection = let
            baseSettings = haproxyConfig."backend kubernetes-api-backend";
            serverLines = map (node: "    server ${node.name} ${node.ip}:6443 check check-ssl verify none inter 2s fall 3 rise 2") cfg.masterNodes;
          in
            concatStringsSep "\n" (
              ["backend kubernetes-api-backend"]
              ++ (
                mapAttrsToList (
                  k: v:
                    if isList v
                    then "    ${concatStringsSep " " v}"
                    else "    ${k} ${v}"
                ) (filterAttrs (k: _v: k != "server") baseSettings)
              )
              ++ serverLines
            );
        in ''
          ${concatStringsSep "\n\n" [
            (mkSection "global" haproxyConfig.global)
            (mkSection "defaults" haproxyConfig.defaults)
            (mkSection "stats stats" haproxyConfig."stats stats")
            (mkSection "frontend kubernetes-api" haproxyConfig."frontend kubernetes-api")
            backendSection
            (mkSection "frontend health" haproxyConfig."frontend health")
            (mkSection "backend health-backend" haproxyConfig."backend health-backend")
          ]}
        '';
      };

      # ========================================================================
      # KEEPALIVED - VIP MANAGEMENT
      # ========================================================================
      keepalived = {
        enable = true;

        vrrpInstances = {
          kubernetes-vip = {
            state =
              if cfg.priority >= 110
              then "MASTER"
              else "BACKUP";
            inherit (cfg) interface;
            virtualRouterId = 51;
            inherit (cfg) priority;
            trackInterface = [cfg.interface];

            virtualIps = [
              {
                addr = "${cfg.vip}/32";
              }
            ];

            scripts = {
              check_haproxy = {
                script = "killall -0 haproxy";
                interval = 2;
                weight = -20;
              };
              check_apiserver = {
                script = "nc -z 127.0.0.1 6443 || exit 1";
                interval = 2;
                weight = -20;
              };
            };
          };
        };
      };

      # ========================================================================
      # PROMETHEUS EXPORTER
      # ========================================================================
      prometheus.exporters.haproxy = mkIf config.services.prometheus.enable {
        enable = true;
        telemetryEndpoint = "http://localhost:8404/stats;csv";
      };
    };

    # ============================================================================
    # FIREWALL
    # ========================================================================
    networking.firewall = {
      allowedTCPPorts = [
        6443 # Kubernetes API (via HAProxy)
        8404 # HAProxy statistics
        8080 # Health check endpoint
      ];
      # VRRP for keepalived
      allowedUDPPorts = [112];
      # Allow VRRP multicast
      extraCommands = ''
        iptables -A INPUT -p vrrp -j ACCEPT
        iptables -A INPUT -d 224.0.0.0/24 -j ACCEPT
      '';
    };

    # ========================================================================
    # SYSTEMD TMPFILES
    # ========================================================================
    systemd.tmpfiles.rules = [
      "d /var/lib/haproxy 0755 haproxy haproxy - -"
      "d /run/haproxy 0755 haproxy haproxy - -"
    ];
  };
}

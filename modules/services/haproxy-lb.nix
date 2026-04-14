{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.services.haproxy-kubernetes;

  haproxyConfig = {
    defaults = {
      log = "global";
      mode = "tcp";
      option = [
        "tcplog"
        "dontlognull"
      ];
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
      daemon = false;
      maxconn = 4000;
    };

    "stats stats" = {
      mode = "http";
      bind = "*:8404";
      stats = {
        enable = true;
        hide-version = true;
        uri = "/";
        realm = "HAProxy Statistics";
        auth = "admin:changeme";
      };
    };

    "frontend kubernetes-api" = {
      bind = "${cfg.vip}:6443";
      mode = "tcp";
      option = [ "tcplog" ];
      defaultBackend = "kubernetes-api-backend";
    };

    "backend kubernetes-api-backend" = {
      mode = "tcp";
      option = [
        "tcp-check"
        "tcplog"
      ];
      balance = "roundrobin";
      timeout = {
        connect = "5s";
        server = "5s";
      };
    };

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
in
{
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
      type = types.listOf (
        types.submodule {
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
        }
      );
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
    services = {
      haproxy = {
        enable = true;

        config =
          let
            mkSection =
              name: settings:
              concatStringsSep "\n" (
                [ "${name}" ]
                ++ (mapAttrsToList (
                  k: v:
                  if isList v then
                    "    ${concatStringsSep " " v}"
                  else if isAttrs v then
                    concatStringsSep "\n" (mapAttrsToList (k2: v2: "    ${k2} ${v2}") v)
                  else
                    "    ${k} ${v}"
                ) settings)
              );

            backendSection =
              let
                baseSettings = haproxyConfig."backend kubernetes-api-backend";
                serverLines = map (
                  node: "    server ${node.name} ${node.ip}:6443 check check-ssl verify none inter 2s fall 3 rise 2"
                ) cfg.masterNodes;
              in
              concatStringsSep "\n" (
                [ "backend kubernetes-api-backend" ]
                ++ (mapAttrsToList (k: v: if isList v then "    ${concatStringsSep " " v}" else "    ${k} ${v}") (
                  filterAttrs (k: _v: k != "server") baseSettings
                ))
                ++ serverLines
              );
          in
          ''
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

      keepalived = {
        enable = true;

        vrrpInstances = {
          kubernetes-vip = {
            state = if cfg.priority >= 110 then "MASTER" else "BACKUP";
            inherit (cfg) interface;
            virtualRouterId = 51;
            inherit (cfg) priority;
            trackInterface = [ cfg.interface ];

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

      prometheus.exporters.haproxy = mkIf config.services.prometheus.enable {
        enable = true;
        telemetryEndpoint = "http://localhost:8404/stats;csv";
      };
    };

    networking.firewall = {
      allowedTCPPorts = lib.mkOptionDefault [
        6443
        8404
        8080
      ];
      allowedUDPPorts = [ 112 ];
      extraInputRules = ''
        ip protocol vrrp accept
        ip daddr 224.0.0.0/24 accept
      '';
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/haproxy 0755 haproxy haproxy - -"
      "d /run/haproxy 0755 haproxy haproxy - -"
    ];
  };
}

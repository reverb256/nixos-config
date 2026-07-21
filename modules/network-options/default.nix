{ lib, ports, cluster }: let
  inherit (lib) mkOption types;
in {
  networking.cluster = mkOption {
    type = types.submodule {
      options = {
        subnet = mkOption {
          type = types.str;
          default = cluster.subnet;
          description = "Cluster subnet";
        };

        gateway = mkOption {
          type = types.str;
          default = cluster.gateway or "10.1.1.1";
          description = "Cluster gateway";
        };

        dnsServers = mkOption {
          type = types.listOf types.str;
          default = ["127.0.0.1" "::1"];
          description = "Legacy DNS servers list (use dns submodule instead)";
        };

        hosts = mkOption {
          type = types.attrsOf (types.submodule {
            options = {
              ip = mkOption {
                type = types.str;
                description = "Host IP address";
              };

              tailscale = mkOption {
                type = types.str;
                description = "Tailscale IP address";
              };

              description = mkOption {
                type = types.str;
                description = "Host description";
              };

              roles = mkOption {
                type = types.listOf types.str;
                description = "Host roles";
              };

              advertiseRoutes = mkOption {
                type = types.listOf types.str;
                default = [];
                description = "Routes to advertise via Tailscale";
              };
            };
          });
          default = {
            zephyr = {
              ip = cluster.hosts.zephyr.ip;
              tailscale = "100.81.182.5";
              description = "Master Workstation - 32 cores, RTX 3090";
              roles = ["desktop" "gaming" "vr" "mining" "build" "ai"];
              advertiseRoutes = ["10.1.1.0/24"];
            };

            nexus = {
              ip = cluster.hosts.nexus.ip;
              tailscale = "100.86.158.18";
              description = "Build/AIStor Server - 24 cores, 1x RTX 3060 Ti";
              roles = ["desktop" "gaming" "vr" "mining" "build" "storage"];
              advertiseRoutes = [];
            };

            forge = {
              ip = cluster.hosts.forge.ip;
              tailscale = "100.95.222.45";
              description = "GPU Mining - 6 cores, 2x RTX 4060 + 2x RX 5700 XT";
              roles = ["mining" "build"];
              advertiseRoutes = ["10.1.1.0/24"];
            };

            sentry = {
              ip = cluster.hosts.sentry.ip;
              tailscale = "100.82.210.39";
              description = "Monitoring Server - 16 cores, RX 5600 XT";
              roles = ["monitoring" "build"];
              advertiseRoutes = ["10.1.1.0/24"];
            };

          };
          description = "Cluster host configurations";
        };

        tailscale = mkOption {
          type = types.submodule {
            options = {
              domain = mkOption {
                type = types.str;
                default = "taila21e09.ts.net";
                description = "Tailscale domain";
              };

              dnsServer = mkOption {
                type = types.str;
                default = "100.100.100.100";
                description = "Tailscale DNS server";
              };
            };
          };
          default = {};
          description = "Tailscale configuration";
        };

        ports = mkOption {
          type = types.submodule {
            options = {
              wivrn-tcp = mkOption { type = types.int; default = 9757; };
              wivrn-udp-start = mkOption { type = types.int; default = 9757; };
              wivrn-udp-end = mkOption { type = types.int; default = 9760; };
              mcp-api = mkOption { type = types.int; default = 18789; };
              mcp-storage = mkOption { type = types.int; default = 18790; };
              steam-tcp = mkOption { type = types.listOf types.int; default = [27031 27036]; };
              steam-udp = mkOption { type = types.listOf types.int; default = [27031 27036]; };
              mdns = mkOption { type = types.int; default = 5353; };
              localsend = mkOption { type = types.int; default = 53317; };
              nix-cache = mkOption { type = types.int; default = 8080; };
              prometheus = mkOption { type = types.int; default = 9090; };
              alertmanager = mkOption { type = types.int; default = 9093; };
              grafana = mkOption { type = types.int; default = 3001; };
              node-exporter = mkOption { type = types.int; default = 9100; };
              nvidia-exporter = mkOption { type = types.int; default = 9400; };
              caddy-admin = mkOption { type = types.int; default = 2019; };
              caddy-http = mkOption { type = types.int; default = 80; };
              caddy-https = mkOption { type = types.int; default = 443; };
              caddy-nodeport-http = mkOption { type = types.int; default = 30080; };
              caddy-nodeport-https = mkOption { type = types.int; default = 30443; };
            };
          };
          default = {};
          description = "Well-known port numbers";
        };

        kubernetes = mkOption {
          type = types.submodule {
            options = {
              vip = mkOption { type = types.str; default = cluster.kubernetes.vip; };
              apiPort = mkOption { type = types.int; default = cluster.kubernetes.apiPort; };
              clusterDnsIP = mkOption {
                type = types.str;
                default = cluster.kubernetes.clusterDnsIP;
                description = "CoreDNS service ClusterIP for cluster.local resolution";
              };
              nodePorts = mkOption {
                type = types.attrsOf types.int;
                default = ports;
                readOnly = true;
                description = "K8s NodePort allocations (derived from kubernetes/service-ports.nix)";
              };
              services = mkOption {
                type = types.submodule {
                  options = let
                    svcOpts = { namespace, port, nodePort ? null, ... }: { name, ... }: {
                      options = {
                        dns = mkOption {
                          type = types.str;
                          default = "${name}.${namespace}.svc.cluster.local:${toString port}";
                          description = "K8s service DNS name (stable across recreations)";
                        };
                        namespace = mkOption { type = types.str; default = namespace; };
                        port = mkOption { type = types.int; default = port; };
                        lan = mkOption { type = types.str; default = ""; description = "LAN hostname"; };
                        nodePort = mkOption { type = types.nullOr types.int; default = nodePort; };
                      };
                    };
                  in {
                    ai-gateway = mkOption { type = types.submodule (svcOpts { namespace = "ai-inference"; port = 8080; }); default = {}; };
                    qdrant = mkOption { type = types.submodule (svcOpts { namespace = "ai-inference"; port = 6333; }); default = {}; };
                    redis = mkOption { type = types.submodule (svcOpts { namespace = "ai-inference"; port = 6379; }); default = {}; };
                    prometheus = mkOption { type = types.submodule (svcOpts { namespace = "ai-inference"; port = 9090; }); default = {}; };
                    searxng = mkOption { type = types.submodule (svcOpts { namespace = "search"; port = 8080; }); default = {}; };
                    vane = mkOption { type = types.submodule (svcOpts { namespace = "search"; port = 30900; }); default = {}; };
                    knowledge-fabric = mkOption { type = types.submodule (svcOpts { namespace = "ai-inference"; port = 3000; }); default = {}; };
                    privacy-filter = mkOption { type = types.submodule (svcOpts { namespace = "ai-inference"; port = 8080; }); default = {}; };
                    n8n = mkOption { type = types.submodule (svcOpts { namespace = "automation"; port = 5678; }); default = {}; };
                    casdoor = mkOption { type = types.submodule (svcOpts { namespace = "auth"; port = 8000; }); default = {}; };
                    oauth2-proxy = mkOption { type = types.submodule (svcOpts { namespace = "auth"; port = 4180; }); default = {}; };
                    haven = mkOption { type = types.submodule (svcOpts { namespace = "haven"; port = 3000; }); default = {}; };
                    mission-control = mkOption { type = types.submodule (svcOpts { namespace = "orchestration"; port = 3000; }); default = {}; };
                    grafana = mkOption { type = types.submodule (svcOpts { namespace = "monitoring"; port = 3000; }); default = {}; };
                    llama-zephyr = mkOption { type = types.submodule (svcOpts { namespace = "ai-inference"; port = 1235; }); default = {}; };
                    llama-zephyr-3060ti = mkOption { type = types.submodule (svcOpts { namespace = "ai-inference"; port = 8040; }); default = {}; };
                    llama-sentry = mkOption { type = types.submodule (svcOpts { namespace = "ai-inference"; port = 1235; }); default = {}; };
                  };
                };
                default = {};
                description = "Kubernetes service endpoints";
              };
            };
          };
          default = {
            vip = cluster.kubernetes.vip;
            apiPort = cluster.kubernetes.apiPort;
          };
          description = "Kubernetes cluster configuration";
        };

        dns = mkOption {
          type = types.submodule {
            options = {
              enable = lib.mkEnableOption "Cluster DNS configuration";
              upstreamServers = mkOption {
                type = types.listOf types.str;
                default = ["1.1.1.1@853" "1.0.0.1@853" "8.8.8.8@853" "8.8.4.4@853"];
                description = "Upstream DNS servers for non-cluster queries (DoT)";
              };
              searchDomains = mkOption {
                type = types.listOf types.str;
                default = ["lan" "cluster.local" "taila21e09.ts.net"];
                description = "DNS search domains";
              };
              listenAddress = mkOption {
                type = types.str;
                default = "";
                description = "IP address for unbound to listen on (defaults to host IP)";
              };
              enableLanRecords = mkOption {
                type = types.bool;
                default = true;
                description = "Generate .lan DNS records for all cluster hosts";
              };
              enableServiceRecords = mkOption {
                type = types.bool;
                default = true;
                description = "Generate .lan DNS records for common services";
              };
            };
          };
          default = {
            enable = false;
            upstreamServers = ["1.1.1.1@853" "1.0.0.1@853" "8.8.8.8@853" "8.8.4.4@853"];
            searchDomains = ["lan" "cluster.local" "taila21e09.ts.net"];
            enableLanRecords = true;
            enableServiceRecords = true;
          };
          description = "Cluster DNS configuration";
        };

        devices = mkOption {
          type = types.submodule {
            options = {
              printer = mkOption { type = types.str; default = "10.1.1.173"; description = "HP ENVY Photo 7800"; };
              switch = mkOption { type = types.str; default = "10.1.1.1"; description = "Core switch"; };
              switch-1 = mkOption { type = types.str; default = "10.1.1.10"; };
              switch-2 = mkOption { type = types.str; default = "10.1.1.11"; };
              switch-3 = mkOption { type = types.str; default = "10.1.1.12"; };
              switch-4 = mkOption { type = types.str; default = "10.1.1.13"; };
            };
          };
          default = {};
          description = "Infrastructure device IPs (printers, switches)";
        };
      };
    };
    default = {};
    description = "Cluster network configuration";
  };
}

{lib, ...}: let
  # Import helpers that route to the SSOT (kubernetes/service-ports.nix + cluster.nix)
  helpers = import ./port-helpers.nix {inherit lib;};
  inherit (helpers) ports;
  inherit (helpers) cluster;
in {
  options.networking.cluster = lib.mkOption {
    type = lib.types.submodule {
      options = {
        subnet = lib.mkOption {
          type = lib.types.str;
          default = cluster.subnet;
          description = "Cluster subnet";
        };

        gateway = lib.mkOption {
          type = lib.types.str;
          default = cluster.gateway or "10.1.1.1";
          description = "Cluster gateway";
        };

        dnsServers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = ["127.0.0.1" "::1"];
          description = "Legacy DNS servers list (use dns submodule instead)";
        };

        hosts = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule {
            options = {
              ip = lib.mkOption {
                type = lib.types.str;
                description = "Host IP address";
              };

              tailscale = lib.mkOption {
                type = lib.types.str;
                description = "Tailscale IP address";
              };

              description = lib.mkOption {
                type = lib.types.str;
                description = "Host description";
              };

              roles = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                description = "Host roles";
              };

              advertiseRoutes = lib.mkOption {
                type = lib.types.listOf lib.types.str;
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

            krash3 = {
              ip = cluster.hosts.krash3.ip;
              tailscale = "100.95.222.46";
              description = "Windows VM Host - 12 cores, RTX 4060";
              roles = ["desktop" "gaming" "mining" "build"];
              advertiseRoutes = ["10.1.1.0/24"];
            };
          };
          description = "Cluster host configurations";
        };

        tailscale = lib.mkOption {
          type = lib.types.submodule {
            options = {
              domain = lib.mkOption {
                type = lib.types.str;
                default = "taila21e09.ts.net";
                description = "Tailscale domain";
              };

              dnsServer = lib.mkOption {
                type = lib.types.str;
                default = "100.100.100.100";
                description = "Tailscale DNS server";
              };
            };
          };
          default = {};
          description = "Tailscale configuration";
        };

        ports = lib.mkOption {
          type = lib.types.submodule {
            options = {
              wivrn-tcp = lib.mkOption {
                type = lib.types.int;
                default = 9757;
              };
              wivrn-udp-start = lib.mkOption {
                type = lib.types.int;
                default = 9757;
              };
              wivrn-udp-end = lib.mkOption {
                type = lib.types.int;
                default = 9760;
              };
              mcp-api = lib.mkOption {
                type = lib.types.int;
                default = 18789;
              };
              mcp-storage = lib.mkOption {
                type = lib.types.int;
                default = 18790;
              };
              steam-tcp = lib.mkOption {
                type = lib.types.listOf lib.types.int;
                default = [27031 27036];
              };
              steam-udp = lib.mkOption {
                type = lib.types.listOf lib.types.int;
                default = [27031 27036];
              };
              mdns = lib.mkOption {
                type = lib.types.int;
                default = 5353;
              };
              localsend = lib.mkOption {
                type = lib.types.int;
                default = 53317;
              };
              xmrig-api = lib.mkOption {
                type = lib.types.int;
                default = 8081;
              };
              lolminer-nvidia-api = lib.mkOption {
                type = lib.types.int;
                default = 4068;
              };
              lolminer-amd-api = lib.mkOption {
                type = lib.types.int;
                default = 4069;
              };
              nix-cache = lib.mkOption {
                type = lib.types.int;
                default = 8080;
              };
              prometheus = lib.mkOption {
                type = lib.types.int;
                default = 9090;
              };
              alertmanager = lib.mkOption {
                type = lib.types.int;
                default = 9093;
              };
              grafana = lib.mkOption {
                type = lib.types.int;
                default = 3001;
              };
              node-exporter = lib.mkOption {
                type = lib.types.int;
                default = 9100;
              };
              nvidia-exporter = lib.mkOption {
                type = lib.types.int;
                default = 9400;
              };
              caddy-admin = lib.mkOption {
                type = lib.types.int;
                default = 2019;
              };
              caddy-http = lib.mkOption {
                type = lib.types.int;
                default = 80;
              };
              caddy-https = lib.mkOption {
                type = lib.types.int;
                default = 443;
              };
              caddy-nodeport-http = lib.mkOption {
                type = lib.types.int;
                default = 30080;
              };
              caddy-nodeport-https = lib.mkOption {
                type = lib.types.int;
                default = 30443;
              };
            };
          };
          default = {};
          description = "Well-known port numbers";
        };

        kubernetes = lib.mkOption {
          type = lib.types.submodule {
            options = {
              vip = lib.mkOption {
                type = lib.types.str;
                default = cluster.kubernetes.vip;
                description = "Kubernetes VIP address";
              };

              apiPort = lib.mkOption {
                type = lib.types.int;
                default = cluster.kubernetes.apiPort;
                description = "Kubernetes API port";
              };

              clusterDnsIP = lib.mkOption {
                type = lib.types.str;
                default = cluster.kubernetes.clusterDnsIP;
                description = "CoreDNS service ClusterIP for cluster.local resolution";
              };

              # NodePort values derived from service-ports.nix (SSOT).
              # Read-only convenience accessor for NixOS modules.
              nodePorts = lib.mkOption {
                type = lib.types.attrsOf lib.types.int;
                default = ports;
                readOnly = true;
                description = "K8s NodePort allocations (derived from kubernetes/service-ports.nix)";
              };

              services = lib.mkOption {
                type = lib.types.submodule {
                  options = let
                    svcOpts = {
                      namespace,
                      port,
                      nodePort ? null,
                      ...
                    }: {name, ...}: {
                      options = {
                        dns = lib.mkOption {
                          type = lib.types.str;
                          default = "${name}.${namespace}.svc.cluster.local:${toString port}";
                          description = "K8s service DNS name (stable across recreations)";
                        };
                        namespace = lib.mkOption {
                          type = lib.types.str;
                          default = namespace;
                        };
                        port = lib.mkOption {
                          type = lib.types.int;
                          default = port;
                        };
                        lan = lib.mkOption {
                          type = lib.types.str;
                          default = "";
                          description = "LAN hostname for this service (if exposed via ingress)";
                        };
                        nodePort = lib.mkOption {
                          type = lib.types.nullOr lib.types.int;
                          default = nodePort;
                        };
                      };
                    };
                  in {
                    ai-gateway = lib.mkOption {
                      type = lib.types.submodule (svcOpts {
                        namespace = "ai-inference";
                        port = 8080;
                      });
                      default = {};
                      description = "AI Inference Gateway";
                    };

                    qdrant = lib.mkOption {
                      type = lib.types.submodule (svcOpts {
                        namespace = "ai-inference";
                        port = 6333;
                      });
                      default = {};
                      description = "Qdrant vector database";
                    };

                    redis = lib.mkOption {
                      type = lib.types.submodule (svcOpts {
                        namespace = "ai-inference";
                        port = 6379;
                      });
                      default = {};
                      description = "Redis cache";
                    };

                    prometheus = lib.mkOption {
                      type = lib.types.submodule (svcOpts {
                        namespace = "ai-inference";
                        port = 9090;
                      });
                      default = {};
                      description = "Prometheus metrics";
                    };

                    searxng = lib.mkOption {
                      type = lib.types.submodule (svcOpts {
                        namespace = "search";
                        port = 8080;
                      });
                      default = {};
                      description = "SearXNG meta search engine";
                    };

                    vane = lib.mkOption {
                      type = lib.types.submodule (svcOpts {
                        namespace = "search";
                        port = 30900;
                      });
                      default = {};
                      description = "Vane search cache";
                    };

                    knowledge-fabric = lib.mkOption {
                      type = lib.types.submodule (svcOpts {
                        namespace = "ai-inference";
                        port = 3000;
                      });
                      default = {};
                      description = "Knowledge Fabric API";
                    };

                    privacy-filter = lib.mkOption {
                      type = lib.types.submodule (svcOpts {
                        namespace = "ai-inference";
                        port = 8080;
                      });
                      default = {};
                      description = "Privacy filter service";
                    };

                    n8n = lib.mkOption {
                      type = lib.types.submodule (svcOpts {
                        namespace = "automation";
                        port = 5678;
                      });
                      default = {};
                      description = "n8n workflow automation";
                    };

                    casdoor = lib.mkOption {
                      type = lib.types.submodule (svcOpts {
                        namespace = "auth";
                        port = 8000;
                      });
                      default = {};
                      description = "Casdoor SSO / OIDC provider";
                    };
                    oauth2-proxy = lib.mkOption {
                      type = lib.types.submodule (svcOpts {
                        namespace = "auth";
                        port = 4180;
                      });
                      default = {};
                      description = "OAuth2 proxy (auth middleware)";
                    };

                    haven = lib.mkOption {
                      type = lib.types.submodule (svcOpts {
                        namespace = "haven";
                        port = 3000;
                      });
                      default = {};
                      description = "Haven dashboard";
                    };

                    mission-control = lib.mkOption {
                      type = lib.types.submodule (svcOpts {
                        namespace = "orchestration";
                        port = 3000;
                      });
                      default = {};
                      description = "Mission Control (builderz-labs)";
                    };

                    grafana = lib.mkOption {
                      type = lib.types.submodule (svcOpts {
                        namespace = "monitoring";
                        port = 3000;
                      });
                      default = {};
                      description = "Grafana dashboards";
                    };
                    llama-zephyr = lib.mkOption {
                      type = lib.types.submodule (svcOpts {
                        namespace = "ai-inference";
                        port = 1235;
                      });
                      default = {};
                      description = "llama-server Zephyr RTX 3090";
                    };

                    llama-zephyr-3060ti = lib.mkOption {
                      type = lib.types.submodule (svcOpts {
                        namespace = "ai-inference";
                        port = 8040;
                      });
                      default = {};
                      description = "vLLM Zephyr RTX 3060 Ti (Qwen3.5-4B-AWQ)";
                    };

                    llama-sentry = lib.mkOption {
                      type = lib.types.submodule (svcOpts {
                        namespace = "ai-inference";
                        port = 1235;
                      });
                      default = {};
                      description = "llama-server Sentry ROCm";
                    };

                    xmrig-proxy = lib.mkOption {
                      type = lib.types.submodule {
                        options = {
                          host = lib.mkOption {
                            type = lib.types.str;
                            default = "10.1.1.120";
                            description = "xmrig-proxy host (not a K8s DNS service)";
                          };
                          port = lib.mkOption {
                            type = lib.types.int;
                            default = 3333;
                          };
                        };
                      };
                      default = {};
                      description = "xmrig-proxy stratum endpoint";
                    };
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

        dns = lib.mkOption {
          type = lib.types.submodule {
            options = {
              enable = lib.mkEnableOption "Cluster DNS configuration";

              upstreamServers = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [
                  "1.1.1.1@853"
                  "1.0.0.1@853"
                  "8.8.8.8@853"
                  "8.8.4.4@853"
                ];
                description = "Upstream DNS servers for non-cluster queries (DoT)";
              };

              searchDomains = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = ["lan" "cluster.local" "taila21e09.ts.net"];
                description = "DNS search domains";
              };

              listenAddress = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "IP address for unbound to listen on (defaults to host IP)";
              };

              enableLanRecords = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Generate .lan DNS records for all cluster hosts";
              };

              enableServiceRecords = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Generate .lan DNS records for common services";
              };
            };
          };
          default = {
            enable = false;
            upstreamServers = [
              "1.1.1.1@853"
              "1.0.0.1@853"
              "8.8.8.8@853"
              "8.8.4.4@853"
            ];
            searchDomains = ["lan" "cluster.local" "taila21e09.ts.net"];
            enableLanRecords = true;
            enableServiceRecords = true;
          };
          description = "Cluster DNS configuration";
        };
        devices = lib.mkOption {
          type = lib.types.submodule {
            options = {
              printer = lib.mkOption {
                type = lib.types.str;
                default = "10.1.1.173";
                description = "HP ENVY Photo 7800";
              };
              switch-1 = lib.mkOption {
                type = lib.types.str;
                default = "10.1.1.10";
              };
              switch-2 = lib.mkOption {
                type = lib.types.str;
                default = "10.1.1.11";
              };
              switch-3 = lib.mkOption {
                type = lib.types.str;
                default = "10.1.1.12";
              };
              switch-4 = lib.mkOption {
                type = lib.types.str;
                default = "10.1.1.13";
              };
            };
          };
          default = {};
          description = "Infrastructure device IPs (printers, switches)";
        };
      };
    };
    description = "Cluster network configuration";
    default = {};
  };
}

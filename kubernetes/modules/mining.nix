# Mining namespace — CPU miners (xmrig) and GPU miners (lolMiner)
# All deployments use nix-csi for /nix store access
#
# Converted from: kubernetes-manifests/mining/
# Key improvement: store paths derived from pkgs, not hardcoded
{
  pkgs,
  config,
  lib,
  ...
}:
let
  # Derive nix-csi scratch image from the cluster's deployed version
  nixCsiScratch = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
in
{
  config.kubernetes.objects = {
    # ── Namespace ──────────────────────────────────────────────
    none.Namespace.mining = {
      metadata.labels = {
        name = "mining";
        workload = "crypto-mining";
      };
    };

    # ── ServiceAccount + RBAC ──────────────────────────────────
    mining.ServiceAccount.gpu-miner-sa = { };
    mining.Role.gpu-miner-role = {
      rules = [
        {
          apiGroups = [ "" ];
          resources = [ "configmaps" ];
          verbs = [
            "get"
            "list"
          ];
        }
      ];
    };
    mining.RoleBinding.gpu-miner-rolebinding = {
      subjects = [
        {
          kind = "ServiceAccount";
          name = "gpu-miner-sa";
          namespace = "mining";
        }
      ];
      roleRef = {
        kind = "Role";
        name = "gpu-miner-role";
        apiGroup = "rbac.authorization.k8s.io";
      };
    };

    # ── Resource Quota ─────────────────────────────────────────
    mining.ResourceQuota.mining-quota = {
      metadata.labels.app = "mining";
      spec.hard = {
        requests.cpu = "25";
        limits.cpu = "50";
        requests.memory = "50Gi";
        limits.memory = "100Gi";
        requests."nvidia.com/gpu" = "5";
        limits."nvidia.com/gpu" = "5";
        "count/pods" = "50";
        "count/deployments.apps" = "20";
      };
    };

    # ── Network Policies ───────────────────────────────────────
    mining.NetworkPolicy.default-deny-all = {
      spec = {
        podSelector = { };
        policyTypes = [
          "Ingress"
          "Egress"
        ];
      };
    };
    mining.NetworkPolicy.xmrig-proxy-policy = {
      spec = {
        podSelector.matchLabels.app = "xmrig-proxy";
        policyTypes = [
          "Ingress"
          "Egress"
        ];
        ingress = [
          {
            from = [
              { namespaceSelector.matchLabels.name = "mining"; }
              { podSelector = { }; }
            ];
            ports = [
              {
                protocol = "TCP";
                port = 3333;
              }
            ];
          }
          {
            from = [ { namespaceSelector.matchLabels.name = "monitoring"; } ];
            ports = [
              {
                protocol = "TCP";
                port = 8081;
              }
            ];
          }
        ];
        egress = [
          {
            to = [ { namespaceSelector = { }; } ];
            ports = [
              {
                protocol = "UDP";
                port = 53;
              }
              {
                protocol = "TCP";
                port = 53;
              }
            ];
          }
          {
            to = [
              {
                ipBlock = {
                  cidr = "0.0.0.0/0";
                  except = [
                    "10.0.0.0/8"
                    "172.16.0.0/12"
                    "192.168.0.0/16"
                  ];
                };
              }
            ];
            ports = [
              {
                protocol = "TCP";
                port = 443;
              }
              {
                protocol = "TCP";
                port = 8038;
              }
              {
                protocol = "TCP";
                port = 8040;
              }
            ];
          }
        ];
      };
    };
    mining.NetworkPolicy.xmrig-miner-policy = {
      spec = {
        podSelector.matchLabels.app = "xmrig";
        policyTypes = [ "Egress" ];
        egress = [
          {
            to = [ { podSelector.matchLabels.app = "xmrig-proxy"; } ];
            ports = [
              {
                protocol = "TCP";
                port = 3333;
              }
            ];
          }
          {
            to = [ { ipBlock.cidr = "10.1.1.0/24"; } ];
            ports = [
              {
                protocol = "TCP";
                port = 3333;
              }
            ];
          }
          {
            to = [ { namespaceSelector = { }; } ];
            ports = [
              {
                protocol = "UDP";
                port = 53;
              }
              {
                protocol = "TCP";
                port = 53;
              }
            ];
          }
        ];
      };
    };
    mining.NetworkPolicy.gpu-miner-policy = {
      spec = {
        podSelector.matchLabels.app = "gpu-miner";
        policyTypes = [ "Egress" ];
        egress = [
          {
            to = [ { podSelector.matchLabels.app = "xmrig-proxy"; } ];
            ports = [
              {
                protocol = "TCP";
                port = 3333;
              }
            ];
          }
          {
            to = [ { ipBlock.cidr = "10.1.1.0/24"; } ];
            ports = [
              {
                protocol = "TCP";
                port = 3333;
              }
            ];
          }
          {
            to = [ { namespaceSelector = { }; } ];
            ports = [
              {
                protocol = "UDP";
                port = 53;
              }
              {
                protocol = "TCP";
                port = 53;
              }
            ];
          }
        ];
      };
    };

    # ── XMRig Deployments (nix-csi) ───────────────────────────
    # Each miner connects to the xmrig-proxy on nexus (10.1.1.120:3333)
    # Uses nix-csi to mount the xmrig binary from /nix/store

    mining.Deployment.xmrig-zephyr = {
      metadata = {
        labels = {
          app = "xmrig-zephyr";
          host = "zephyr";
          workload = "crypto-mining";
        };
        annotations = {
          "prometheus.io/scrape" = "true";
          "prometheus.io/port" = "8082";
          "prometheus.io/path" = "/1/summary";
        };
      };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "xmrig-zephyr";
        strategy.type = "Recreate";
        template = {
          metadata.labels = {
            app = "xmrig-zephyr";
            host = "zephyr";
            workload = "crypto-mining";
          };
          spec = {
            nodeName = "zephyr";
            hostNetwork = true;
            hostIPC = true;
            dnsPolicy = "ClusterFirstWithHostNet";
            automountServiceAccountToken = false;
            serviceAccountName = "gpu-miner-sa";
            priorityClassName = "mining-low";
            tolerations = {
              _namedlist = true;
              control-plane = {
                key = "node-role.kubernetes.io/control-plane";
                operator = "Exists";
                effect = "NoSchedule";
              };
              workstation = {
                key = "workstation";
                operator = "Equal";
                value = "true";
                effect = "NoSchedule";
              };
              interactive = {
                key = "interactive";
                operator = "Equal";
                value = "true";
                effect = "NoExecute";
              };
              ram-constrained = {
                key = "ram-constrained";
                operator = "Equal";
                value = "true";
                effect = "NoSchedule";
              };
            };
            containers = {
              _namedlist = true;
              xmrig = {
                image = nixCsiScratch;
                command = [ (lib.getExe pkgs.xmrig) ];
                args = [
                  "-o"
                  "10.1.1.120:3333"
                  "-u"
                  "zephyr-cpu"
                  "--tls=false"
                  "--threads=16"
                  "--donate-level=1"
                  "--http-enabled"
                  "--http-host=0.0.0.0"
                  "--http-port=8082"
                  "--api-worker-id=zephyr-cpu"
                ];
                env = {
                  _namedlist = true;
                };
                ports = [
                  {
                    containerPort = 8082;
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  httpGet = {
                    path = "/1/summary";
                    port = 8082;
                  };
                  initialDelaySeconds = 30;
                  periodSeconds = 30;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/1/summary";
                    port = 8082;
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 10;
                  failureThreshold = 3;
                };
                resources = {
                  requests = {
                    memory = "1Gi";
                    cpu = "4";
                  };
                  limits = {
                    memory = "4096Mi";
                    cpu = "8";
                  };
                };
                securityContext.privileged = true;
                volumeMounts = {
                  _namedlist = true;
                  nix = {
                    mountPath = "/nix";
                    subPath = "nix";
                  };
                  msr = {
                    mountPath = "/dev/cpu";
                  };
                  hugepages = {
                    mountPath = "/dev/hugepages";
                  };
                  sys-module-msr = {
                    mountPath = "/sys/module/msr";
                  };
                  tmp = {
                    mountPath = "/tmp";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              nix = {
                csi = {
                  driver = "nix.csi.store";
                  volumeAttributes.${pkgs.system} = pkgs.xmrig;
                };
              };
              msr = {
                hostPath = {
                  path = "/dev/cpu";
                  type = "Directory";
                };
              };
              hugepages = {
                hostPath = {
                  path = "/dev/hugepages";
                  type = "Directory";
                };
              };
              sys-module-msr = {
                hostPath = {
                  path = "/sys/module/msr";
                  type = "Directory";
                };
              };
              tmp = {
                emptyDir = { };
              };
            };
          };
        };
      };
    };

    mining.Deployment.xmrig-nexus = {
      metadata = {
        labels.app = "xmrig-nexus";
        annotations = {
          "prometheus.io/scrape" = "true";
          "prometheus.io/port" = "8082";
          "prometheus.io/path" = "/1/summary";
        };
      };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "xmrig-nexus";
        strategy.type = "Recreate";
        template = {
          metadata.labels.app = "xmrig-nexus";
          spec = {
            nodeName = "nexus";
            hostNetwork = true;
            hostIPC = true;
            dnsPolicy = "ClusterFirstWithHostNet";
            automountServiceAccountToken = false;
            serviceAccountName = "gpu-miner-sa";
            priorityClassName = "mining-low";
            tolerations = [
              {
                key = "node-role.kubernetes.io/control-plane";
                operator = "Exists";
                effect = "NoSchedule";
              }
            ];
            containers = {
              _namedlist = true;
              xmrig = {
                image = nixCsiScratch;
                command = [ (lib.getExe pkgs.xmrig) ];
                args = [
                  "-o"
                  "10.1.1.120:3333"
                  "-u"
                  "nexus-cpu"
                  "--tls=false"
                  "--threads=6"
                  "--donate-level=1"
                  "--http-enabled"
                  "--http-host=0.0.0.0"
                  "--http-port=8082"
                  "--api-worker-id=nexus-cpu"
                ];
                ports = [
                  {
                    containerPort = 8082;
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  httpGet = {
                    path = "/1/summary";
                    port = 8082;
                  };
                  initialDelaySeconds = 30;
                  periodSeconds = 30;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/1/summary";
                    port = 8082;
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 10;
                  failureThreshold = 3;
                };
                resources = {
                  requests = {
                    memory = "1Gi";
                    cpu = "3";
                  };
                  limits = {
                    memory = "3072Mi";
                    cpu = "6";
                  };
                };
                securityContext.privileged = true;
                volumeMounts = {
                  _namedlist = true;
                  nix = {
                    mountPath = "/nix";
                    subPath = "nix";
                  };
                  msr = {
                    mountPath = "/dev/cpu";
                  };
                  hugepages = {
                    mountPath = "/dev/hugepages";
                  };
                  sys-module-msr = {
                    mountPath = "/sys/module/msr";
                  };
                  tmp = {
                    mountPath = "/tmp";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              nix = {
                csi = {
                  driver = "nix.csi.store";
                  volumeAttributes.${pkgs.system} = pkgs.xmrig;
                };
              };
              msr = {
                hostPath = {
                  path = "/dev/cpu";
                  type = "Directory";
                };
              };
              hugepages = {
                hostPath = {
                  path = "/dev/hugepages";
                  type = "Directory";
                };
              };
              sys-module-msr = {
                hostPath = {
                  path = "/sys/module/msr";
                  type = "Directory";
                };
              };
              tmp = {
                emptyDir = { };
              };
            };
          };
        };
      };
    };

    mining.Deployment.xmrig-sentry = {
      metadata = {
        labels.app = "xmrig-sentry";
        annotations = {
          "prometheus.io/scrape" = "true";
          "prometheus.io/port" = "8082";
          "prometheus.io/path" = "/1/summary";
        };
      };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "xmrig-sentry";
        strategy.type = "Recreate";
        template = {
          metadata.labels.app = "xmrig-sentry";
          spec = {
            nodeName = "sentry";
            hostNetwork = true;
            hostIPC = true;
            dnsPolicy = "ClusterFirstWithHostNet";
            automountServiceAccountToken = false;
            serviceAccountName = "gpu-miner-sa";
            priorityClassName = "mining-low";
            containers = {
              _namedlist = true;
              xmrig = {
                image = nixCsiScratch;
                command = [ (lib.getExe pkgs.xmrig) ];
                args = [
                  "-o"
                  "10.1.1.120:3333"
                  "-u"
                  "sentry-cpu"
                  "--tls=false"
                  "--threads=8"
                  "--donate-level=1"
                  "--http-enabled"
                  "--http-host=0.0.0.0"
                  "--http-port=8082"
                  "--api-worker-id=sentry-cpu"
                ];
                ports = [
                  {
                    containerPort = 8082;
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  httpGet = {
                    path = "/1/summary";
                    port = 8082;
                  };
                  initialDelaySeconds = 30;
                  periodSeconds = 30;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/1/summary";
                    port = 8082;
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 10;
                  failureThreshold = 3;
                };
                resources = {
                  requests = {
                    memory = "1Gi";
                    cpu = "4";
                  };
                  limits = {
                    memory = "3072Mi";
                    cpu = "8";
                  };
                };
                securityContext.privileged = true;
                volumeMounts = {
                  _namedlist = true;
                  nix = {
                    mountPath = "/nix";
                    subPath = "nix";
                  };
                  msr = {
                    mountPath = "/dev/cpu";
                  };
                  hugepages = {
                    mountPath = "/dev/hugepages";
                  };
                  sys-module-msr = {
                    mountPath = "/sys/module/msr";
                  };
                  tmp = {
                    mountPath = "/tmp";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              nix = {
                csi = {
                  driver = "nix.csi.store";
                  volumeAttributes.${pkgs.system} = pkgs.xmrig;
                };
              };
              msr = {
                hostPath = {
                  path = "/dev/cpu";
                  type = "Directory";
                };
              };
              hugepages = {
                hostPath = {
                  path = "/dev/hugepages";
                  type = "Directory";
                };
              };
              sys-module-msr = {
                hostPath = {
                  path = "/sys/module/msr";
                  type = "Directory";
                };
              };
              tmp = {
                emptyDir = { };
              };
            };
          };
        };
      };
    };
  };
}

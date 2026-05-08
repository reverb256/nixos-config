{
  pkgs,
  config,
  lib,
  cluster,
  ...
}: let
  nixCsiScratch = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
  nexusIP = cluster.hosts.nexus.ip;
  xmrigProxy = "${nexusIP}:3333";
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
  cfg = config.kubernetes.manifests.mining;
in {
  options.kubernetes.manifests.mining = {
    enableZephyr = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable XMRig CPU miner on zephyr";
    };
    enableNexus = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable XMRig CPU miner on nexus";
    };
    enableSentry = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable XMRig CPU miner on sentry";
    };
  };

  config.kubernetes.objects = {
    none.Namespace.mining = {
      metadata.labels =
        managed
        // {
          name = "mining";
          workload = "crypto-mining";
        };
    };

    mining.ServiceAccount.gpu-miner-sa = {};
    mining.Role.gpu-miner-role = {
      rules = [
        {
          apiGroups = [""];
          resources = ["configmaps"];
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

    mining.NetworkPolicy.default-deny-all = {
      spec = {
        podSelector = {};
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
              {namespaceSelector.matchLabels.name = "mining";}
              {podSelector = {};}
            ];
            ports = [
              {
                protocol = "TCP";
                port = 3333;
              }
            ];
          }
          {
            from = [{namespaceSelector.matchLabels.name = "monitoring";}];
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
            to = [{namespaceSelector = {};}];
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
        policyTypes = ["Egress"];
        egress = [
          {
            to = [{podSelector.matchLabels.app = "xmrig-proxy";}];
            ports = [
              {
                protocol = "TCP";
                port = 3333;
              }
            ];
          }
          {
            to = [{ipBlock.cidr = cluster.subnet;}];
            ports = [
              {
                protocol = "TCP";
                port = 3333;
              }
            ];
          }
          {
            to = [{namespaceSelector = {};}];
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
        policyTypes = ["Egress"];
        egress = [
          {
            to = [{podSelector.matchLabels.app = "xmrig-proxy";}];
            ports = [
              {
                protocol = "TCP";
                port = 3333;
              }
            ];
          }
          {
            to = [{ipBlock.cidr = cluster.subnet;}];
            ports = [
              {
                protocol = "TCP";
                port = 3333;
              }
            ];
          }
          {
            to = [{namespaceSelector = {};}];
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

    mining.Deployment.xmrig-zephyr = lib.mkIf cfg.enableZephyr {
      metadata = {
        labels =
          managed
          // {
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
          metadata = {
            labels =
              managed
              // {
                app = "xmrig-zephyr";
                host = "zephyr";
                workload = "crypto-mining";
              };
            annotations."nix-csi/discard" = "true";
          };
          spec = {
            nodeName = "zephyr";
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
              {
                key = "workstation";
                operator = "Equal";
                value = "true";
                effect = "NoSchedule";
              }
              {
                key = "interactive";
                operator = "Equal";
                value = "true";
                effect = "NoExecute";
              }
              {
                key = "ram-constrained";
                operator = "Equal";
                value = "true";
                effect = "NoSchedule";
              }
            ];
            containers = {
              _namedlist = true;
              xmrig = {
                image = nixCsiScratch;
                command = ["${lib.getExe pkgs.xmrig}"];
                args = [
                  "-o"
                  "${xmrigProxy}"
                  "-u"
                  "zephyr-cpu"
                  "--tls=true"
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
                    readOnly = true;
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
              nix.hostPath = {
                path = "/nix";
                type = "Directory";
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
                emptyDir = {};
              };
            };
          };
        };
      };
    };

    mining.Deployment.xmrig-nexus = lib.mkIf cfg.enableNexus {
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
          metadata.labels = managed // {app = "xmrig-nexus";};
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
                command = ["${lib.getExe pkgs.xmrig}"];
                args = [
                  "-o"
                  "${xmrigProxy}"
                  "-u"
                  "nexus-cpu"
                  "--tls=true"
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
                    readOnly = true;
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
              nix.hostPath = {
                path = "/nix";
                type = "Directory";
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
                emptyDir = {};
              };
            };
          };
        };
      };
    };

    mining.ConfigMap.xmrig-proxy-config = {
      metadata.labels =
        managed
        // {
          app = "xmrig-proxy";
          component = "stratum-proxy";
        };
      data."config.json" = builtins.toJSON {
        bind = [
          {
            host = "0.0.0.0";
            port = 3333;
          }
        ];
        api = {
          port = 8081;
          restricted = true;
          "token-file" = "/etc/xmrig-proxy-secrets/api-token";
        };
        randomx.mode = "light";
        log.level = 5;
        pools = [
          {
            id = "kryptex-rx-us";
            url = "xtm-rx-us.kryptex.network:8038";
            user = "krxXVNVMM7.cpu-proxy";
            "pass-file" = "/etc/xmrig-proxy-secrets/pool-password";
            tls = true;
            keepalive = true;
            priority = 1;
          }
          {
            id = "kryptex-rx-eu";
            url = "xtm-rx-eu.kryptex.network:8038";
            user = "krxXVNVMM7.cpu-proxy";
            "pass-file" = "/etc/xmrig-proxy-secrets/pool-password";
            tls = true;
            keepalive = true;
            priority = 2;
          }
          {
            id = "kryptex-cr29-us";
            url = "xtm-c29-us.kryptex.network:8040";
            user = "krxXVNVMM7.gpu-proxy";
            "pass-file" = "/etc/xmrig-proxy-secrets/pool-password";
            tls = true;
            keepalive = true;
            priority = 1;
          }
          {
            id = "kryptex-cr29-eu";
            url = "xtm-c29-eu.kryptex.network:8040";
            user = "krxXVNVMM7.gpu-proxy";
            "pass-file" = "/etc/xmrig-proxy-secrets/pool-password";
            tls = true;
            keepalive = true;
            priority = 2;
          }
        ];
        workers = [
          {
            id = "zephyr-cpu";
            "password-file" = "/etc/xmrig-proxy-secrets/pool-password";
          }
          {
            id = "nexus-cpu";
            "password-file" = "/etc/xmrig-proxy-secrets/pool-password";
          }
          {
            id = "sentry-cpu";
            "password-file" = "/etc/xmrig-proxy-secrets/pool-password";
          }
          {
            id = "zephyr-gpu";
            "password-file" = "/etc/xmrig-proxy-secrets/pool-password";
          }
          {
            id = "nexus-gpu";
            "password-file" = "/etc/xmrig-proxy-secrets/pool-password";
          }
          {
            id = "forge-gpu";
            "password-file" = "/etc/xmrig-proxy-secrets/pool-password";
          }
          {
            id = "forge-gpu-nvidia";
            "password-file" = "/etc/xmrig-proxy-secrets/pool-password";
          }
          {
            id = "forge-gpu-amd";
            "password-file" = "/etc/xmrig-proxy-secrets/pool-password";
          }
        ];
      };
    };

    mining.Secret.xmrig-proxy-secret = {
      metadata.labels =
        managed
        // {
          app = "xmrig-proxy";
          component = "stratum-proxy";
        };
      type = "Opaque";
      stringData = {
        # Populated by kubectl-apply-k8s-secrets from agenix:
        #   api-token ← /run/agenix/xmrig-proxy-api-token
        "api-token" = "";
        "kryptex-password" = "x";
      };
    };

    mining.Deployment.xmrig-proxy = {
      metadata = {
        labels =
          managed
          // {
            app = "xmrig-proxy";
            component = "stratum-proxy";
          };
        annotations = {
          "prometheus.io/scrape" = "true";
          "prometheus.io/port" = "8081";
        };
      };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "xmrig-proxy";
        strategy = {
          type = "RollingUpdate";
          rollingUpdate = {
            maxSurge = 0;
            maxUnavailable = 1;
          };
        };
        template = {
          metadata.labels =
            managed
            // {
              app = "xmrig-proxy";
              component = "stratum-proxy";
            };
          spec = {
            nodeName = "nexus";
            hostNetwork = true;
            serviceAccountName = "gpu-miner-sa";
            automountServiceAccountToken = false;
            priorityClassName = "system-cluster-critical";
            tolerations = [
              {
                key = "node-role.kubernetes.io/control-plane";
                operator = "Exists";
                effect = "NoSchedule";
              }
            ];
            containers = {
              _namedlist = true;
              xmrig-proxy = {
                image = "xmrig-proxy:nixos-6.24.0";
                imagePullPolicy = "Never";
                args = [
                  "--config=/etc/xmrig-proxy/config.json"
                  "--no-color"
                ];
                ports = [
                  {
                    containerPort = 3333;
                    name = "stratum";
                    protocol = "TCP";
                  }
                  {
                    containerPort = 8081;
                    name = "api";
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  tcpSocket.port = "stratum";
                  initialDelaySeconds = 15;
                  periodSeconds = 20;
                  timeoutSeconds = 5;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  tcpSocket.port = "stratum";
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
                  timeoutSeconds = 3;
                  failureThreshold = 3;
                };
                resources = {
                  requests = {
                    memory = "128Mi";
                    cpu = "100m";
                  };
                  limits = {
                    memory = "1Gi";
                    cpu = "1000m";
                  };
                };
                securityContext.capabilities.drop = ["ALL"];
                volumeMounts = {
                  _namedlist = true;
                  nix = {
                    mountPath = "/nix";
                    readOnly = true;
                  };
                  config = {
                    mountPath = "/etc/xmrig-proxy";
                  };
                  secrets = {
                    mountPath = "/etc/xmrig-proxy-secrets";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              nix.hostPath = {
                path = "/nix";
                type = "Directory";
              };
              config.configMap.name = "xmrig-proxy-config";
              secrets = {
                secret = {
                  secretName = "xmrig-proxy-secret";
                  items = [
                    {
                      key = "api-token";
                      path = "api-token";
                    }
                    {
                      key = "kryptex-password";
                      path = "pool-password";
                    }
                  ];
                };
              };
            };
          };
        };
      };
    };

    mining.Service.xmrig-proxy = {
      metadata.labels = managed // {app = "xmrig-proxy";};
      spec = {
        type = "ClusterIP";
        selector.app = "xmrig-proxy";
        sessionAffinity = "ClientIP";
        ports = [
          {
            name = "stratum";
            port = 3333;
            targetPort = 3333;
            protocol = "TCP";
          }
          {
            name = "metrics";
            port = 8081;
            targetPort = 8081;
            protocol = "TCP";
          }
        ];
      };
    };

    # --- LimitRange for mining namespace ---
    mining.LimitRange.mining-limits = {
      metadata.labels = managed // {app = "gpu-scheduler";};
      spec.limits = [
        {
          default = {
            cpu = "2";
            memory = "4Gi";
          };
          defaultRequest = {
            cpu = "100m";
            memory = "100Mi";
          };
          max = {
            cpu = "8";
            memory = "16Gi";
          };
          type = "Container";
        }
      ];
    };

    # --- ResourceQuota for mining namespace ---
    mining.ResourceQuota.mining-quota = {
      metadata.labels = managed // {app = "mining";};
      spec.hard = {
        "requests.cpu" = "25";
        "limits.cpu" = "50";
        "requests.memory" = "50Gi";
        "limits.memory" = "100Gi";
        "requests.nvidia.com/gpu" = "5";
        "limits.nvidia.com/gpu" = "5";
        "count/pods" = "50";
        "count/deployments.apps" = "20";
      };
    };

    # --- PriorityClasses for mining workloads ---
    none.PriorityClass.mining-low = {
      value = -10;
      preemptionPolicy = "PreemptLowerPriority";
      globalDefault = false;
      description =
        "Low priority for crypto mining workloads"
        + " - preempted by AI inference and other higher-priority workloads";
    };
    none.PriorityClass.preemptible-mining = {
      value = -20;
      preemptionPolicy = "PreemptLowerPriority";
      globalDefault = false;
      description =
        "Preemptible priority for mining"
        + " - evicted by any higher priority workload";
    };

    # --- PodDisruptionBudget for xmrig-proxy ---
    mining.PodDisruptionBudget.xmrig-proxy-pdb = {
      metadata.labels = managed // {app = "xmrig-proxy";};
      spec = {
        maxUnavailable = 1;
        selector.matchLabels.app = "xmrig-proxy";
      };
    };

    # --- OpenCL ICD ConfigMap for AMD GPUs ---
    mining.ConfigMap.opencl-icd-vendors = {
      data."amdocl64.icd" = "${pkgs.rocmPackages.clr}/lib/libamdocl64.so\n";
    };

    # --- XMRig CPU Miner - sentry (8 cores, 8 threads = 50%) ---
    mining.Deployment.xmrig-sentry = lib.mkIf cfg.enableSentry {
      metadata.labels =
        managed
        // {
          app = "xmrig-sentry";
          host = "sentry";
          workload = "crypto-mining";
        };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "xmrig-sentry";
        strategy.type = "Recreate";
        template = {
          metadata = {
            labels =
              managed
              // {
                app = "xmrig-sentry";
                host = "sentry";
                workload = "crypto-mining";
              };
            annotations = {
              "prometheus.io/scrape" = "true";
              "prometheus.io/port" = "8082";
              "prometheus.io/path" = "/1/summary";
            };
          };
          spec = {
            nodeName = "sentry";
            serviceAccountName = "gpu-miner-sa";
            automountServiceAccountToken = false;
            priorityClassName = "mining-low";
            hostNetwork = true;
            hostIPC = true;
            hostPID = true;
            dnsPolicy = "ClusterFirstWithHostNet";
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
                imagePullPolicy = "IfNotPresent";
                command = ["${lib.getExe pkgs.xmrig}"];
                args = [
                  "-o"
                  "${xmrigProxy}"
                  "-u"
                  "sentry-cpu"
                  "--tls=true"
                  "--threads=8"
                  "--donate-level=1"
                  "--http-enabled"
                  "--http-host=0.0.0.0"
                  "--http-port=8082"
                ];
                ports = [
                  {
                    containerPort = 8082;
                    name = "api";
                    protocol = "TCP";
                  }
                ];
                resources = {
                  requests = {
                    memory = "2Gi";
                    cpu = "4";
                  };
                  limits = {
                    memory = "4Gi";
                    cpu = "8";
                  };
                };
                securityContext.privileged = true;
                volumeMounts = {
                  _namedlist = true;
                  nix = {
                    mountPath = "/nix";
                    readOnly = true;
                  };
                  msr = {
                    mountPath = "/dev/cpu";
                    mountPropagation = "HostToContainer";
                  };
                  hugepages = {
                    mountPath = "/dev/hugepages";
                    mountPropagation = "HostToContainer";
                  };
                  sys-module-msr = {
                    mountPath = "/sys/module/msr";
                    mountPropagation = "HostToContainer";
                  };
                  tmp = {
                    mountPath = "/tmp";
                  };
                };
                livenessProbe = {
                  httpGet = {
                    path = "/1/summary";
                    port = 8082;
                  };
                  initialDelaySeconds = 30;
                  periodSeconds = 30;
                  timeoutSeconds = 5;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/1/summary";
                    port = 8082;
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 10;
                  timeoutSeconds = 5;
                  failureThreshold = 3;
                };
              };
            };
            volumes = {
              _namedlist = true;
              nix.hostPath = {
                path = "/nix";
                type = "Directory";
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
                emptyDir = {};
              };
            };
          };
        };
      };
    };
  };
}

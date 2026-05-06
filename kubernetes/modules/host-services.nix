{
  pkgs,
  pkgsWithOverlay,
  inputs,
  config,
  lib,
  ...
}: let
  scratchImage = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
  xmrigProxy = "stratum+tcp://10.1.1.120:3333";
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };

  # Common hostPath volume for Nix store (nix-csi pattern)
  nixVolume = {
    hostPath.path = "/nix";
    type = "Directory";
  };
  nixVolumeMount = {
    mountPath = "/nix/store";
  };

  # Common host volume patterns
  hostVolume = path: {
    hostPath.path = path;
    type =
      if lib.hasSuffix "/" path
      then "Directory"
      else "DirectoryOrCreate";
  };

  # All cluster nodes for DaemonSets
  allTolerations = [
    {
      key = "node-role.kubernetes.io/control-plane";
      operator = "Exists";
      effect = "NoSchedule";
    }
    {
      key = "workstation";
      operator = "Exists";
    }
    {
      key = "interactive";
      operator = "Exists";
    }
    {
      key = "ram-constrained";
      operator = "Exists";
    }
  ];
in {
  config.kubernetes.objects = {
    # ── Namespace ──────────────────────────────────────────────────
    none.Namespace.infra = {
      metadata.labels.name = "infra";
    };

    infra.NetworkPolicy.default-deny-infra = {
      spec = {
        podSelector = {};
        policyTypes = ["Ingress"];
      };
    };

    # ── Redis (StatefulSet) ────────────────────────────────────────
    # Replaces: redis.service + redis-ai-gateway.service on zephyr+nexus
    infra.StatefulSet.redis = {
      metadata.labels =
        managed
        // {
          app = "redis";
        };
      spec = {
        serviceName = "redis";
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "redis";
        template = {
          metadata.labels =
            managed
            // {
              app = "redis";
            };
          spec = {
            nodeName = "zephyr";
            hostNetwork = true;
            dnsPolicy = "ClusterFirstWithHostNet";
            automountServiceAccountToken = false;
            priorityClassName = "system-cluster-critical";
            tolerations = allTolerations;
            containers = {
              _namedlist = true;
              redis = {
                image = scratchImage;
                imagePullPolicy = "IfNotPresent";
                command = ["${pkgs.redis}/bin/redis-server"];
                args = [
                  "--port"
                  "6379"
                  "--bind"
                  "0.0.0.0"
                  "--appendonly"
                  "yes"
                  "--dir"
                  "/data"
                  "--maxmemory"
                  "256mb"
                  "--maxmemory-policy"
                  "allkeys-lru"
                  "--save"
                  "60"
                  "1000"
                  "--save"
                  "300"
                  "100"
                ];
                ports = [
                  {
                    containerPort = 6379;
                    name = "redis";
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  exec.command = [
                    "${pkgs.redis}/bin/redis-cli"
                    "ping"
                  ];
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
                };
                readinessProbe = {
                  exec.command = [
                    "${pkgs.redis}/bin/redis-cli"
                    "ping"
                  ];
                  initialDelaySeconds = 3;
                  periodSeconds = 5;
                };
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "512Mi";
                  };
                };
                securityContext.capabilities.drop = ["ALL"];
                volumeMounts = {
                  _namedlist = true;
                  nix = nixVolumeMount;
                  data = {
                    mountPath = "/data";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              nix = nixVolume;
            };
          };
        };
        volumeClaimTemplates = [
          {
            metadata.name = "data";
            spec = {
              accessModes = ["ReadWriteOncePod"];
              storageClassName = "local-path";
              resources.requests.storage = "1Gi";
            };
          }
        ];
      };
    };

    infra.Service.redis = {
      metadata.labels =
        managed
        // {
          app = "redis";
        };
      spec = {
        type = "ClusterIP";
        selector.app = "redis";
        ports = [
          {
            name = "redis";
            port = 6379;
            targetPort = 6379;
            protocol = "TCP";
          }
        ];
      };
    };

    # ── Redis AI Gateway (StatefulSet) ─────────────────────────────
    # Separate Redis instance for AI gateway cache on zephyr
    infra.StatefulSet.redis-ai-gateway = {
      metadata.labels =
        managed
        // {
          app = "redis-ai-gateway";
        };
      spec = {
        serviceName = "redis-ai-gateway";
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "redis-ai-gateway";
        template = {
          metadata.labels =
            managed
            // {
              app = "redis-ai-gateway";
            };
          spec = {
            nodeName = "zephyr";
            hostNetwork = true;
            dnsPolicy = "ClusterFirstWithHostNet";
            automountServiceAccountToken = false;
            priorityClassName = "system-cluster-critical";
            tolerations = allTolerations;
            containers = {
              _namedlist = true;
              redis = {
                image = scratchImage;
                imagePullPolicy = "IfNotPresent";
                command = ["${pkgs.redis}/bin/redis-server"];
                args = [
                  "--port"
                  "6380"
                  "--bind"
                  "0.0.0.0"
                  "--appendonly"
                  "yes"
                  "--dir"
                  "/data"
                  "--maxmemory"
                  "512mb"
                  "--maxmemory-policy"
                  "allkeys-lru"
                ];
                ports = [
                  {
                    containerPort = 6380;
                    name = "redis";
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  exec.command = [
                    "${pkgs.redis}/bin/redis-cli"
                    "-p"
                    "6380"
                    "ping"
                  ];
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
                };
                resources = {
                  requests = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                  limits = {
                    cpu = "500m";
                    memory = "512Mi";
                  };
                };
                securityContext.capabilities.drop = ["ALL"];
                volumeMounts = {
                  _namedlist = true;
                  nix = nixVolumeMount;
                  data = {
                    mountPath = "/data";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              nix = nixVolume;
            };
          };
        };
        volumeClaimTemplates = [
          {
            metadata.name = "data";
            spec = {
              accessModes = ["ReadWriteOncePod"];
              storageClassName = "local-path";
              resources.requests.storage = "2Gi";
            };
          }
        ];
      };
    };

    infra.Service.redis-ai-gateway = {
      metadata.labels =
        managed
        // {
          app = "redis-ai-gateway";
        };
      spec = {
        type = "ClusterIP";
        selector.app = "redis-ai-gateway";
        ports = [
          {
            name = "redis";
            port = 6380;
            targetPort = 6380;
            protocol = "TCP";
          }
        ];
      };
    };

    # ── Prometheus Node Exporter (DaemonSet) ───────────────────────
    # Replaces: prometheus-node-exporter.service on all 4 nodes
    infra.DaemonSet.node-exporter = {
      metadata.labels =
        managed
        // {
          app = "node-exporter";
        };
      spec = {
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "node-exporter";
        template = {
          metadata = {
            labels =
              managed
              // {
                app = "node-exporter";
              };
            annotations."prometheus.io/scrape" = "true";
            annotations."prometheus.io/port" = "9100";
          };
          spec = {
            hostNetwork = true;
            hostPID = true;
            dnsPolicy = "ClusterFirstWithHostNet";
            automountServiceAccountToken = false;
            tolerations = allTolerations;
            containers = {
              _namedlist = true;
              node-exporter = {
                image = scratchImage;
                imagePullPolicy = "IfNotPresent";
                command = ["${pkgs.prometheus-node-exporter}/bin/node_exporter"];
                args = [
                  "--web.listen-address=0.0.0.0:9100"
                  "--path.rootfs=/host/root"
                  "--path.sysfs=/host/sys"
                  "--path.procfs=/host/proc"
                  "--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|run/k3s/containerd/.+|var/lib/docker/.+|var/lib/containers/.+)($$|/)"
                  "--collector.systemd"
                  "--no-collector.btrfs"
                ];
                ports = [
                  {
                    containerPort = 9100;
                    name = "metrics";
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  httpGet = {
                    path = "/";
                    port = 9100;
                  };
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
                };
                resources = {
                  requests = {
                    memory = "32Mi";
                    cpu = "25m";
                  };
                  limits = {
                    memory = "128Mi";
                    cpu = "100m";
                  };
                };
                securityContext = {
                  runAsNonRoot = true;
                  runAsUser = 65534;
                };
                volumeMounts = {
                  _namedlist = true;
                  nix = nixVolumeMount;
                  root = {
                    mountPath = "/host/root";
                    readOnly = true;
                  };
                  sys = {
                    mountPath = "/host/sys";
                    readOnly = true;
                  };
                  proc = {
                    mountPath = "/host/proc";
                    readOnly = true;
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              nix = nixVolume;
              root.hostPath = {
                path = "/";
                type = "Directory";
              };
              sys.hostPath = {
                path = "/sys";
                type = "Directory";
              };
              proc.hostPath = {
                path = "/proc";
                type = "Directory";
              };
            };
          };
        };
      };
    };

    # ── NVIDIA GPU Exporter (DaemonSet) ────────────────────────────
    # Replaces: prometheus-nvidia-gpu-exporter.service on nvidia nodes
    infra.DaemonSet.nvidia-gpu-exporter = {
      metadata.labels =
        managed
        // {
          app = "nvidia-gpu-exporter";
        };
      spec = {
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "nvidia-gpu-exporter";
        template = {
          metadata = {
            labels =
              managed
              // {
                app = "nvidia-gpu-exporter";
              };
            annotations."prometheus.io/scrape" = "true";
            annotations."prometheus.io/port" = "9400";
          };
          spec = {
            hostNetwork = true;
            dnsPolicy = "ClusterFirstWithHostNet";
            automountServiceAccountToken = false;
            nodeSelector.accelerator = "nvidia-gpu";
            tolerations = allTolerations;
            containers = {
              _namedlist = true;
              gpu-exporter = {
                image = scratchImage;
                imagePullPolicy = "IfNotPresent";
                command = ["${pkgs.prometheus-nvidia-gpu-exporter}/bin/nvidia_gpu_exporter"];
                args = [
                  "--web.listen-address=0.0.0.0:9400"
                  "--nvidia-smi-command=/run/opengl-driver/lib/nvidia-smi"
                ];
                ports = [
                  {
                    containerPort = 9400;
                    name = "metrics";
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  httpGet = {
                    path = "/";
                    port = 9400;
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 15;
                };
                resources = {
                  requests = {
                    memory = "32Mi";
                    cpu = "25m";
                  };
                  limits = {
                    memory = "128Mi";
                    cpu = "100m";
                  };
                };
                securityContext.privileged = true;
                volumeMounts = {
                  _namedlist = true;
                  nix = nixVolumeMount;
                  opengl = {
                    mountPath = "/run/opengl-driver/lib";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              nix = nixVolume;
              opengl.hostPath.path = "/run/opengl-driver/lib";
            };
          };
        };
      };
    };

    # ── Vaultwarden (Deployment) ──────────────────────────────────
    # Replaces: vaultwarden.service (podman) on zephyr
    infra.Deployment.vaultwarden = {
      metadata.labels =
        managed
        // {
          app = "vaultwarden";
        };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "vaultwarden";
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
              app = "vaultwarden";
            };
          spec = {
            nodeName = "nexus";
            automountServiceAccountToken = false;
            tolerations = allTolerations;
            containers = {
              _namedlist = true;
              vaultwarden = {
                image = "docker.io/vaultwarden/server:1.35.4";
                imagePullPolicy = "IfNotPresent";
                env = {
                  _namedlist = true;
                  WEBSOCKET_ENABLED.value = "true";
                  WEBSOCKET_ADDRESS.value = "0.0.0.0";
                  DOMAIN.value = "https://vaultwarden.zephyr.taila21e09.ts.net";
                  LOG_LEVEL.value = "info";
                  OIDC_CLIENT_ID.value = "45b131ddd1706688495a";
                  OIDC_AUTH_URL.value = "https://auth.lan/authorize";
                  OIDC_TOKEN_URL.value = "https://auth.lan/oauth/token";
                  OIDC_USERINFO_URL.value = "https://auth.lan/api/userinfo";
                  OIDC_SCOPES.value = "openid profile email";
                  OIDC_ADMIN_VALIDATE.value = "true";
                  ADMIN_TOKEN.valueFrom.secretKeyRef = {
                    name = "vaultwarden-secrets";
                    key = "admin-token";
                  };
                  OIDC_CLIENT_SECRET.valueFrom.secretKeyRef = {
                    name = "vaultwarden-secrets";
                    key = "oidc-client-secret";
                  };
                };
                ports = [
                  {
                    containerPort = 80;
                    name = "http";
                    protocol = "TCP";
                  }
                  {
                    containerPort = 3012;
                    name = "websocket";
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  httpGet = {
                    path = "/alive";
                    port = "http";
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 30;
                  timeoutSeconds = 5;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/alive";
                    port = "http";
                  };
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
                  timeoutSeconds = 3;
                };
                resources = {
                  requests = {
                    memory = "64Mi";
                    cpu = "50m";
                  };
                  limits = {
                    memory = "512Mi";
                    cpu = "500m";
                  };
                };
                securityContext.capabilities.drop = ["ALL"];
                volumeMounts = {
                  _namedlist = true;
                  data = {
                    mountPath = "/data";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              data = {
                persistentVolumeClaim = {
                  claimName = "vaultwarden-data";
                };
              };
            };
          };
        };
      };
    };

    infra.Service.vaultwarden = {
      metadata.labels =
        managed
        // {
          app = "vaultwarden";
        };
      spec = {
        type = "NodePort";
        selector.app = "vaultwarden";
        ports = [
          {
            name = "http";
            port = 80;
            targetPort = 80;
            nodePort = 32110;
            protocol = "TCP";
          }
          {
            name = "websocket";
            port = 3012;
            targetPort = 3012;
            nodePort = 32111;
            protocol = "TCP";
          }
        ];
      };
    };

    infra.PersistentVolume.vaultwarden-data-nexus-pv = {
      spec = {
        capacity.storage = "1Gi";
        accessModes = ["ReadWriteOnce"];
        persistentVolumeReclaimPolicy = "Retain";
        storageClassName = "fast-local-ssd";
        local.path = "/data/vaultwarden-data";
        nodeAffinity.required.nodeSelectorTerms = [
          {
            matchExpressions = [
              {
                key = "kubernetes.io/hostname";
                operator = "In";
                values = ["nexus"];
              }
            ];
          }
        ];
      };
    };

    infra.PersistentVolumeClaim.vaultwarden-data = {
      spec = {
        accessModes = ["ReadWriteOnce"];
        storageClassName = "fast-local-ssd";
        resources.requests.storage = "1Gi";
      };
    };

    # ── Claude Code Router (Deployment) ───────────────────────────
    # Replaces: claude-code-router.service on zephyr
    infra.Deployment.claude-code-router = {
      metadata.labels =
        managed
        // {
          app = "claude-code-router";
        };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "claude-code-router";
        strategy.type = "Recreate";
        template = {
          metadata.labels =
            managed
            // {
              app = "claude-code-router";
            };
          spec = {
            nodeName = "zephyr";
            hostNetwork = true;
            dnsPolicy = "ClusterFirstWithHostNet";
            automountServiceAccountToken = false;
            tolerations = allTolerations;
            containers = {
              _namedlist = true;
              router = {
                image = scratchImage;
                imagePullPolicy = "IfNotPresent";
                command = ["${pkgs.nodejs_22}/bin/npx"];
                args = [
                  "@musistudio/claude-code-router"
                  "start"
                  "--port"
                  "3456"
                  "--config"
                  "/config/config.json"
                ];
                env = {
                  _namedlist = true;
                  NODE_ENV.value = "production";
                  HOME.value = "/tmp";
                };
                ports = [
                  {
                    containerPort = 3456;
                    name = "http";
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  httpGet = {
                    path = "/health";
                    port = 3456;
                  };
                  initialDelaySeconds = 15;
                  periodSeconds = 30;
                  failureThreshold = 3;
                };
                resources = {
                  requests = {
                    memory = "64Mi";
                    cpu = "50m";
                  };
                  limits = {
                    memory = "256Mi";
                    cpu = "500m";
                  };
                };
                securityContext.capabilities.drop = ["ALL"];
                volumeMounts = {
                  _namedlist = true;
                  nix = nixVolumeMount;
                  config = {
                    mountPath = "/config";
                  };
                  npm-cache = {
                    mountPath = "/tmp/.npm";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              nix = nixVolume;
              config = {
                hostPath.path = "/var/lib/claude-code-router";
                type = "DirectoryOrCreate";
              };
              npm-cache.emptyDir = {};
            };
          };
        };
      };
    };

    infra.Service.claude-code-router = {
      metadata.labels =
        managed
        // {
          app = "claude-code-router";
        };
      spec = {
        type = "ClusterIP";
        selector.app = "claude-code-router";
        ports = [
          {
            name = "http";
            port = 3456;
            targetPort = 3456;
            protocol = "TCP";
          }
        ];
      };
    };

    # ── AI Inference Monitor (DaemonSet) ──────────────────────────
    # Replaces: ai-inference-monitor.service on zephyr/nexus/sentry
    infra.DaemonSet.ai-inference-monitor = {
      metadata.labels =
        managed
        // {
          app = "ai-inference-monitor";
        };
      spec = {
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "ai-inference-monitor";
        template = {
          metadata = {
            labels =
              managed
              // {
                app = "ai-inference-monitor";
              };
            annotations."prometheus.io/scrape" = "true";
            annotations."prometheus.io/port" = "9190";
          };
          spec = {
            hostNetwork = true;
            dnsPolicy = "ClusterFirstWithHostNet";
            automountServiceAccountToken = false;
            tolerations = allTolerations;
            containers = {
              _namedlist = true;
              monitor = {
                image = scratchImage;
                imagePullPolicy = "IfNotPresent";
                command = [
                  "${pkgs.writeShellScript "ai-inference-monitor" ''
                    exec ${pkgs.python3}/bin/python3 /scripts/monitor.py
                  ''}"
                ];
                env = {
                  _namedlist = true;
                  BACKEND_URL.value = "http://127.0.0.1:1235";
                  GATEWAY_URL.value = "http://0.0.0.0:8080";
                  METRICS_PORT.value = "9190";
                };
                ports = [
                  {
                    containerPort = 9190;
                    name = "metrics";
                    protocol = "TCP";
                  }
                ];
                resources = {
                  requests = {
                    memory = "32Mi";
                    cpu = "25m";
                  };
                  limits = {
                    memory = "128Mi";
                    cpu = "100m";
                  };
                };
                securityContext.capabilities.drop = ["ALL"];
                volumeMounts = {
                  _namedlist = true;
                  nix = nixVolumeMount;
                  scripts = {
                    mountPath = "/scripts";
                    readOnly = true;
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              nix = nixVolume;
              scripts = {
                hostPath.path = "/etc/ai-inference-monitor";
                type = "DirectoryOrCreate";
              };
            };
          };
        };
      };
    };

    # ── Gaming Detection (DaemonSet) ──────────────────────────────
    # Replaces: gaming-detection.service on zephyr/sentry
    # NOTE: Needs host D-Bus and /proc access for game process detection
    infra.DaemonSet.gaming-detection = {
      metadata.labels =
        managed
        // {
          app = "gaming-detection";
        };
      spec = {
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "gaming-detection";
        template = {
          metadata.labels =
            managed
            // {
              app = "gaming-detection";
            };
          spec = {
            hostNetwork = true;
            hostPID = true;
            dnsPolicy = "ClusterFirstWithHostNet";
            automountServiceAccountToken = false;
            tolerations = allTolerations;
            containers = {
              _namedlist = true;
              detector = {
                image = scratchImage;
                imagePullPolicy = "IfNotPresent";
                command = [
                  "${pkgs.writeShellScriptBin "gaming-detection" ''
                    #!/usr/bin/env bash
                    set -euo pipefail
                    # Placeholder - gaming detection is host-bound (needs D-Bus, GameMode)
                    # Real detection runs via NixOS systemd service on the host
                    echo "gaming-detection: running in K8s placeholder mode" >&2
                    STATE_DIR="/run/gaming-detection"
                    mkdir -p "$STATE_DIR"
                    echo "GAMING_ACTIVE=0" > "$STATE_DIR/gaming_state"
                    exec sleep infinity
                  ''}/bin/gaming-detection"
                ];
                resources = {
                  requests = {
                    memory = "32Mi";
                    cpu = "25m";
                  };
                  limits = {
                    memory = "64Mi";
                    cpu = "100m";
                  };
                };
                securityContext.privileged = true;
                volumeMounts = {
                  _namedlist = true;
                  nix = nixVolumeMount;
                  proc = {
                    mountPath = "/host/proc";
                    readOnly = true;
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              nix = nixVolume;
              proc.hostPath = {
                path = "/proc";
                type = "Directory";
              };
            };
          };
        };
      };
    };

    # ── Mining Coordinator (Deployment) ───────────────────────────
    # Replaces: mining-coordinator.service on zephyr/sentry
    # Needs kubectl access to manage K8s mining pods
    infra.ServiceAccount.mining-coordinator = {};
    infra.Role.mining-coordinator = {
      rules = [
        {
          apiGroups = ["apps"];
          resources = ["deployments"];
          verbs = [
            "get"
            "list"
            "patch"
            "scale"
          ];
        }
        {
          apiGroups = [""];
          resources = ["pods"];
          verbs = [
            "get"
            "list"
            "watch"
          ];
        }
      ];
    };
    infra.RoleBinding.mining-coordinator = {
      subjects = [
        {
          kind = "ServiceAccount";
          name = "mining-coordinator";
          namespace = "infra";
        }
      ];
      roleRef = {
        kind = "Role";
        name = "mining-coordinator";
        apiGroup = "rbac.authorization.k8s.io";
      };
    };
    infra.Deployment.mining-coordinator = lib.mkIf (config.services.mining-coordinator.enable or false) {
      metadata.labels =
        managed
        // {
          app = "mining-coordinator";
        };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "mining-coordinator";
        strategy.type = "Recreate";
        template = {
          metadata.labels =
            managed
            // {
              app = "mining-coordinator";
            };
          spec = {
            nodeName = "zephyr";
            hostNetwork = true;
            hostPID = true;
            dnsPolicy = "ClusterFirstWithHostNet";
            serviceAccountName = "mining-coordinator";
            tolerations = allTolerations;
            containers = {
              _namedlist = true;
              coordinator = {
                image = scratchImage;
                imagePullPolicy = "IfNotPresent";
                command = [
                  "${pkgs.writeShellScript "mining-coordinator-entrypoint" ''
                    export PATH=${pkgs.kubectl}/bin:${pkgs.procps}/bin:${pkgs.gawk}/bin:${pkgs.coreutils}/bin:$PATH
                    exec ${config.systemd.services.mining-coordinator.serviceConfig.ExecStart}
                  ''}"
                ];
                resources = {
                  requests = {
                    memory = "32Mi";
                    cpu = "25m";
                  };
                  limits = {
                    memory = "128Mi";
                    cpu = "200m";
                  };
                };
                securityContext.privileged = true;
                volumeMounts = {
                  _namedlist = true;
                  nix = nixVolumeMount;
                };
              };
            };
            volumes = {
              _namedlist = true;
              nix = nixVolume;
            };
          };
        };
      };
    };

    # ── Mining-Inference Coordinator (DaemonSet) ──────────────────
    # Self-contained: monitors llama.cpp on 3090 (port 1237), pauses mining
    # during inference. No 3060Ti fallback — 3060Ti reserved for vLLM.
    # Needs kubectl for scaling, curl for metrics, hostNetwork for localhost.
    infra.DaemonSet.mining-inference-coordinator = {
      metadata.labels =
        managed
        // {
          app = "mining-inference-coordinator";
        };
      spec = {
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "mining-inference-coordinator";
        template = {
          metadata.labels =
            managed
            // {
              app = "mining-inference-coordinator";
            };
          spec = {
            hostNetwork = true;
            hostPID = true;
            dnsPolicy = "ClusterFirstWithHostNet";
            automountServiceAccountToken = false;
            tolerations = allTolerations;
            nodeSelector."kubernetes.io/hostname" = "zephyr";
            containers = {
              _namedlist = true;
              coordinator = {
                image = scratchImage;
                imagePullPolicy = "IfNotPresent";
                command = [
                  "${pkgs.writeShellScript "mining-inference-coord" ''
                    set -uo pipefail
                    export PATH=${pkgs.curl}/bin:${pkgs.gawk}/bin:${pkgs.kubectl}/bin:${pkgs.coreutils}/bin:$PATH

                    LLAMA_PORT="1237"
                    COMFYUI_PORT="8188"
                    PRIMARY="deployment/gpu-miner-zephyr"
                    NS="mining"
                    CHECK_INTERVAL="3"
                    IDLE_TIMEOUT="30"

                    last_tokens_predicted=-1
                    inference_source="unknown"
                    last_inference_time=0
                    mining_shifted=false

                    log() {
                      echo "[$(date '+%H:%M:%S')] $*" >&2
                    }

                    scale() {
                      local resource="$1"
                      local replicas="$2"
                      kubectl scale "$resource" --replicas="$replicas" -n "$NS" 2>/dev/null || true
                    }

                    is_inference_active() {
                      local processing
                      processing=$(curl -sf "http://127.0.0.1:$LLAMA_PORT/metrics" 2>/dev/null \
                        | grep "^llamacpp:requests_processing " \
                        | awk '{print $2}')

                      if [ -n "$processing" ] && [ "$processing" -gt 0 ]; then
                        return 0
                      fi

                      local current_tokens
                      current_tokens=$(curl -sf "http://127.0.0.1:$LLAMA_PORT/metrics" 2>/dev/null \
                        | grep "^llamacpp:tokens_predicted_total " \
                        | awk '{print $2}')

                      if [ -n "$current_tokens" ] && [ "$last_tokens_predicted" -ge 0 ]; then
                        if [ "$current_tokens" -gt "$last_tokens_predicted" ]; then
                          last_tokens_predicted=$current_tokens
                          return 0
                        fi
                      fi

                      if [ -n "$current_tokens" ]; then
                        last_tokens_predicted=$current_tokens
                      fi

                      return 1
                    }

                    is_comfyui_active() {
                      local queue_response
                      queue_response=$(curl -sf "http://127.0.0.1:$COMFYUI_PORT/queue" 2>/dev/null)

                      # ComfyUI not running or unreachable
                      if [ -z "$queue_response" ]; then
                        return 1
                      fi

                      # Running jobs = GPU actively working
                      # Pending jobs = GPU will be used next
                      echo "$queue_response" | grep -qE '"queue_running":\s*\[[^]]' && return 0
                      echo "$queue_response" | grep -qE '"queue_pending":\s*\[[^]]' && return 0

                      return 1
                    }

                    any_inference_active() {
                      inference_source="unknown"
                      if is_inference_active; then
                        inference_source="llama-server"
                        return 0
                      fi
                      if is_comfyui_active; then
                        inference_source="ComfyUI"
                        return 0
                      fi
                      return 1
                    }

                    shift_to_fallback() {
                      local source="''${1:-inference}"
                      scale "$PRIMARY" 0
                      mining_shifted=true
                      log "PAUSED: 3090 miner stopped ($source)"
                    }

                    shift_to_primary() {
                      scale "$PRIMARY" 1
                      mining_shifted=false
                      log "RESUMED: 3090 -> mining"
                    }

                    log "Coordinator started - monitoring :$LLAMA_PORT (llama-server), :$COMFYUI_PORT (ComfyUI)"
                    log "Primary: $PRIMARY (3090)"
                    log "Check interval: ''${CHECK_INTERVAL}s, idle timeout: ''${IDLE_TIMEOUT}s"

                    while true; do
                      current_time=$(date +%s)

                      if any_inference_active; then
                        last_inference_time=$current_time

                        if [ "$mining_shifted" = false ]; then
                          shift_to_fallback "$inference_source"
                        fi
                      else
                        if [ "$mining_shifted" = true ] && [ "$last_inference_time" -gt 0 ]; then
                          idle_time=$((current_time - last_inference_time))

                          if [ "$idle_time" -ge "$IDLE_TIMEOUT" ]; then
                            shift_to_primary
                          fi
                        fi
                      fi

                      sleep "$CHECK_INTERVAL"
                    done
                  ''}"
                ];
                env = {
                  _namedlist = true;
                  NODE_NAME.valueFrom.fieldRef.fieldPath = "spec.nodeName";
                };
                resources = {
                  requests = {
                    memory = "32Mi";
                    cpu = "25m";
                  };
                  limits = {
                    memory = "128Mi";
                    cpu = "200m";
                  };
                };
                securityContext.privileged = true;
                volumeMounts = {
                  _namedlist = true;
                  nix = nixVolumeMount;
                };
              };
            };
            volumes = {
              _namedlist = true;
              nix = nixVolume;
            };
          };
        };
      };
    };

    # ── lolminer-nvidia on zephyr (Deployment) ────────────────────
    # Replaces: lolminer-nvidia.service on zephyr (GPU 1, RTX 3090)
    # Supersedes the CrashLoopBackOff gpu-miner-zephyr pod
    mining.Deployment.lolminer-nvidia-zephyr = {
      metadata.labels =
        managed
        // {
          app = "lolminer-nvidia-zephyr";
          host = "zephyr";
          gpu = "rtx3090";
        };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "lolminer-nvidia-zephyr";
        strategy.type = "Recreate";
        template = {
          metadata.labels =
            managed
            // {
              app = "lolminer-nvidia-zephyr";
              host = "zephyr";
              gpu = "rtx3090";
            };
          spec = {
            nodeName = "zephyr";
            hostNetwork = true;
            dnsPolicy = "ClusterFirstWithHostNet";
            automountServiceAccountToken = false;
            serviceAccountName = "gpu-miner-sa";
            priorityClassName = "mining-low";
            tolerations = allTolerations;
            containers = {
              _namedlist = true;
              lolminer = {
                image = "docker.io/swamp7/lolminer:latest";
                imagePullPolicy = "IfNotPresent";
                args = [
                  "--algo"
                  "CR29"
                  "--pool"
                  "${xmrigProxy}"
                  "--user"
                  "krxXVNVMM7.zephyr-gpu"
                  "--pass"
                  "x"
                  "--tls"
                  "off"
                  "--pool"
                  "xtm-c29-us.kryptex.network:8040"
                  "--user"
                  "krxXVNVMM7.zephyr-gpu"
                  "--pass"
                  "x"
                  "--tls"
                  "on"
                  "--devices"
                  "1"
                  "--apiport"
                  "4068"
                  "--mode"
                  "b"
                ];
                env = {
                  _namedlist = true;
                  GPU_MAX_HEAP_SIZE.value = "100";
                  GPU_MAX_ALLOC_PERCENT.value = "100";
                  OCL_ICD_VENDORS.value = "/etc/OpenCL/vendors";
                };
                ports = [
                  {
                    containerPort = 4068;
                    name = "api";
                    protocol = "TCP";
                  }
                ];
                resources = {
                  requests = {
                    memory = "256Mi";
                    cpu = "100m";
                  };
                  limits = {
                    memory = "2Gi";
                    cpu = "1000m";
                  };
                };
                securityContext.privileged = true;
                volumeMounts = {
                  _namedlist = true;
                  nix = nixVolumeMount;
                  opengl = {
                    mountPath = "/run/opengl-driver/lib";
                  };
                  dev = {
                    mountPath = "/dev";
                  };
                  opencl = {
                    mountPath = "/etc/OpenCL/vendors";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              nix = nixVolume;
              opengl.hostPath.path = "/run/opengl-driver/lib";
              dev.hostPath = {
                path = "/dev";
                type = "Directory";
              };
              opencl.hostPath = {
                path = "/etc/OpenCL/vendors";
                type = "DirectoryOrCreate";
              };
            };
          };
        };
      };
    };

    # ── Caddy Local Proxy (Deployment) ────────────────────────────
    # Replaces: caddy.service on zephyr (local reverse proxy, NOT K8s ingress)
    # Stays on zephyr for local .ts.net domain TLS termination
    infra.Deployment.caddy-local = {
      metadata.labels =
        managed
        // {
          app = "caddy-local";
        };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "caddy-local";
        strategy.type = "Recreate";
        template = {
          metadata.labels =
            managed
            // {
              app = "caddy-local";
            };
          spec = {
            nodeName = "zephyr";
            hostNetwork = true;
            dnsPolicy = "ClusterFirstWithHostNet";
            automountServiceAccountToken = false;
            priorityClassName = "system-cluster-critical";
            tolerations = allTolerations;
            containers = {
              _namedlist = true;
              caddy = {
                image = scratchImage;
                imagePullPolicy = "IfNotPresent";
                command = ["${pkgsWithOverlay.caddy-with-modules}/bin/caddy"];
                args = [
                  "run"
                  "--config"
                  "/etc/caddy/caddy_config"
                  "--adapter"
                  "caddyfile"
                ];
                ports = [
                  {
                    containerPort = 80;
                    name = "http";
                    protocol = "TCP";
                  }
                  {
                    containerPort = 443;
                    name = "https";
                    protocol = "TCP";
                  }
                ];
                livenessProbe = {
                  httpGet = {
                    path = "/";
                    port = 80;
                  };
                  initialDelaySeconds = 5;
                  periodSeconds = 30;
                };
                resources = {
                  requests = {
                    memory = "32Mi";
                    cpu = "25m";
                  };
                  limits = {
                    memory = "256Mi";
                    cpu = "500m";
                  };
                };
                securityContext.capabilities.add = [
                  "NET_ADMIN"
                  "NET_BIND_SERVICE"
                ];
                volumeMounts = {
                  _namedlist = true;
                  nix = nixVolumeMount;
                  config = {
                    mountPath = "/etc/caddy";
                    readOnly = true;
                  };
                  data = {
                    mountPath = "/var/lib/caddy";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              nix = nixVolume;
              config = {
                hostPath.path = "/etc/caddy";
                type = "Directory";
              };
              data = {
                hostPath.path = "/var/lib/caddy";
                type = "DirectoryOrCreate";
              };
            };
          };
        };
      };
    };

    # ── Syncthing (StatefulSet) ───────────────────────────────────
    # Replaces: syncthing.service on zephyr/forge/sentry
    # One instance per node for file sync
    infra.DaemonSet.syncthing = {
      metadata.labels =
        managed
        // {
          app = "syncthing";
        };
      spec = {
        revisionHistoryLimit = 1;
        selector.matchLabels.app = "syncthing";
        template = {
          metadata.labels =
            managed
            // {
              app = "syncthing";
            };
          spec = {
            hostNetwork = true;
            dnsPolicy = "ClusterFirstWithHostNet";
            automountServiceAccountToken = false;
            tolerations = allTolerations;
            containers = {
              _namedlist = true;
              syncthing = {
                image = scratchImage;
                imagePullPolicy = "IfNotPresent";
                command = ["${pkgs.syncthing}/bin/syncthing"];
                args = [
                  "--config=/data/config"
                  "--data=/data/data"
                  "--gui-address=0.0.0.0:8384"
                  "--no-browser"
                ];
                env = {
                  _namedlist = true;
                  HOME.value = "/tmp";
                  STNORESTART.value = "yes";
                  STNOUPGRADE.value = "yes";
                };
                ports = [
                  {
                    containerPort = 8384;
                    name = "gui";
                    protocol = "TCP";
                  }
                  {
                    containerPort = 22000;
                    name = "sync";
                    protocol = "TCP";
                  }
                  {
                    containerPort = 22000;
                    name = "sync-udp";
                    protocol = "UDP";
                  }
                  {
                    containerPort = 21027;
                    name = "discover";
                    protocol = "UDP";
                  }
                ];
                livenessProbe = {
                  httpGet = {
                    path = "/rest/noauth/health";
                    port = 8384;
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 30;
                };
                resources = {
                  requests = {
                    memory = "64Mi";
                    cpu = "50m";
                  };
                  limits = {
                    memory = "512Mi";
                    cpu = "1000m";
                  };
                };
                securityContext.capabilities.drop = ["ALL"];
                volumeMounts = {
                  _namedlist = true;
                  nix = nixVolumeMount;
                  data = {
                    mountPath = "/data";
                  };
                  host-sync = {
                    mountPath = "/sync";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              nix = nixVolume;
              data = {
                emptyDir = {sizeLimit = "1Gi";};
              };
              host-sync.hostPath = {
                path = "/var/lib/syncthing";
                type = "DirectoryOrCreate";
              };
            };
          };
        };
      };
    };
  };
}

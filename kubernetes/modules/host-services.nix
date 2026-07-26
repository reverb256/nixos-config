{
  pkgs,
  pkgsWithOverlay,
  inputs,
  config,
  lib,
  cluster,
  nexusPreferredAffinity,
  ...
}: let
  scratchImage = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
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
      metadata.labels = {
        name = "infra";
        "pod-security.kubernetes.io/enforce" = "baseline";
        "pod-security.kubernetes.io/audit" = "restricted";
        "pod-security.kubernetes.io/warn" = "restricted";
      };
    };

    infra.NetworkPolicy.default-deny-all = {
      spec = {
        podSelector = {};
        policyTypes = ["Ingress" "Egress"];
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
            affinity = nexusPreferredAffinity; # P0: was nodeName "zephyr" — default to nexus (46GB)
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
            affinity = nexusPreferredAffinity; # P0: was nodeName "zephyr" — default to nexus (46GB)
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
            nodeName = "zephyr"; # Local-only: .ts.net TLS termination requires zephyr certs
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

    # ── Syncthing — REMOVED 2026-07-15 — was causing 65+ dirty git files on forge
    # due to .stversions/ from Syncthing file versioning. NixOS services on forge/sentry
    # also disabled. Use rsync or other sync tool if needed in future.
  };
}

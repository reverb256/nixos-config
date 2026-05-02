{lib, ...}: let
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
in {
  # ── AI Coding Tools Namespace ────────────────────────────────────
  # Claude Code and OpenCode AI coding assistants
  # Replaces YAML manifests in kubernetes-manifests/ai-coding-tools/

  config.kubernetes.objects.ai-coding = {
    # ── PersistentVolumeClaim ─────────────────────────────────────
    PersistentVolumeClaim.ai-coding-configs = {
      spec = {
        accessModes = ["ReadWriteOnce"];
        storageClassName = "fast-local-ssd";
        resources.requests.storage = "10Gi";
      };
    };

    # ── Migration Job (one-shot) ─────────────────────────────────
    # Migrates .claude and .opencode configs from host to PVC
    Job.migrate-ai-coding-configs-v2 = {
      spec = {
        template = {
          spec = {
            affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms = [
              {
                matchExpressions = [
                  {
                    key = "kubernetes.io/hostname";
                    operator = "In";
                    values = ["zephyr"];
                  }
                ];
              }
            ];
            containers = [
              {
                name = "migration";
                image = "docker.io/reverb256/claude-code:nixos";
                command = [
                  "/bin/bash"
                  "-c"
                  ''
                    set -e
                    echo "Starting migration..."
                    SRC_HOST="/host-home"
                    DST_PVC="/pvc-home"
                    if [[ -d "$SRC_HOST/.claude" ]]; then
                      mkdir -p "$DST_PVC/.claude"
                      cp -r "$SRC_HOST/.claude/"* "$DST_PVC/.claude/" 2>/dev/null || true
                    fi
                    if [[ -d "$SRC_HOST/.opencode" ]]; then
                      mkdir -p "$DST_PVC/.opencode"
                      cp -r "$SRC_HOST/.opencode/"* "$DST_PVC/.opencode/" 2>/dev/null || true
                    fi
                    sleep 3600
                  ''
                ];
                volumeMounts = [
                  {
                    name = "host-home";
                    mountPath = "/host-home";
                    readOnly = true;
                  }
                  {
                    name = "pvc-home";
                    mountPath = "/pvc-home";
                  }
                ];
              }
            ];
            volumes = [
              {
                name = "host-home";
                hostPath = {
                  path = "/home/j_kro";
                  type = "Directory";
                };
              }
              {
                name = "pvc-home";
                persistentVolumeClaim.claimName = "ai-coding-configs";
              }
            ];
            restartPolicy = "Never";
          };
        };
        backoffLimit = 1;
      };
    };

    # ── Claude Code Deployment (containerized) ───────────────────
    # Replaces: 10-claude-code-deployment.yaml, 10-claude-code-multi-node.yaml,
    #           10-claude-code-simple.yaml, 50-claude-code-containerized.yaml
    Deployment.claude-code = {
      metadata.labels = managed // {
        app = "claude-code";
        component = "ai-coding-tool";
      };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "claude-code";
        strategy = {
          type = "RollingUpdate";
          rollingUpdate = {
            maxSurge = 0;
            maxUnavailable = 1;
          };
        };
        template = {
          metadata = {
            labels = managed // {
              app = "claude-code";
              component = "ai-coding-tool";
            };
            annotations = {
              "prometheus.io/scrape" = "true";
              "prometheus.io/port" = "9090";
              "prometheus.io/path" = "/metrics";
            };
          };
          spec = {
            nodeSelector."kubernetes.io/hostname" = "nexus";
            containers = {
              _namedlist = true;
              claude-code = {
                image = "docker.io/reverb256/claude-code:nixos";
                imagePullPolicy = "Always";
                command = [
                  "/bin/bash"
                  "-c"
                  ''
                    echo "Claude Code container ready"
                    tail -f /dev/null
                  ''
                ];
                env = {
                  _namedlist = true;
                  POD_NAME.valueFrom.fieldRef.fieldPath = "metadata.name";
                  HOME.value = "/home/j_kro";
                  USER.value = "j_kro";
                  CLAUDE_CONFIG_DIR.value = "/home/j_kro/.claude";
                  PATH.value = "/bin:/usr/bin:/home/j_kro/.nix-profile/bin";
                };
                ports = [
                  {
                    containerPort = 8080;
                    name = "http";
                    protocol = "TCP";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "500m";
                    memory = "512Mi";
                  };
                  limits = {
                    cpu = "2000m";
                    memory = "2Gi";
                  };
                };
                volumeMounts = {
                  _namedlist = true;
                  home-dir = {mountPath = "/home/j_kro";};
                };
                livenessProbe = {
                  exec.command = ["/bin/sh" "-c" "test -d /home/j_kro/.claude"];
                  initialDelaySeconds = 10;
                  periodSeconds = 30;
                };
                readinessProbe = {
                  exec.command = ["/bin/sh" "-c" "test -d /home/j_kro/.claude"];
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
                };
              };
              metrics = {
                image = "python:3.11-slim";
                command = [
                  "/bin/sh"
                  "-c"
                  ''
                    pip install prometheus_client psutil -q
                    python3 -c "
                    from prometheus_client import start_http_server, Gauge
                    import psutil, time
                    HISTORY_SIZE = Gauge('claude_history_size_mb', 'History file size MB')
                    CPU_USAGE = Gauge('claude_cpu_usage_percent', 'CPU usage percent')
                    def get_history_size():
                        try:
                            with open('/home/j_kro/.claude/history.jsonl','rb') as f:
                                f.seek(0,2); return f.tell()/(1024*1024)
                        except: return 0
                    start_http_server(9090)
                    while True:
                        HISTORY_SIZE.set(get_history_size())
                        CPU_USAGE.set(psutil.cpu_percent(interval=1))
                        time.sleep(10)
                    "
                  ''
                ];
                env = {
                  _namedlist = true;
                  HOME.value = "/home/j_kro";
                };
                ports = [
                  {
                    containerPort = 9090;
                    name = "metrics";
                    protocol = "TCP";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "50m";
                    memory = "64Mi";
                  };
                  limits = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                };
                volumeMounts = {
                  _namedlist = true;
                  home-dir = {
                    mountPath = "/home/j_kro";
                    readOnly = true;
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              home-dir.persistentVolumeClaim.claimName = "ai-coding-configs";
            };
            terminationGracePeriodSeconds = 30;
          };
        };
      };
    };

    # ── Claude Code HPA ──────────────────────────────────────────
    # Replaces: 30-hpa.yaml (claude-code-hpa portion), 50-claude-code-containerized.yaml HPA
    HorizontalPodAutoscaler.claude-code-hpa = {
      spec = {
        scaleTargetRef = {
          apiVersion = "apps/v1";
          kind = "Deployment";
          name = "claude-code";
        };
        minReplicas = 1;
        maxReplicas = 4;
        metrics = [
          {
            type = "Resource";
            resource = {
              name = "cpu";
              target = {
                type = "Utilization";
                averageUtilization = 70;
              };
            };
          }
          {
            type = "Resource";
            resource = {
              name = "memory";
              target = {
                type = "Utilization";
                averageUtilization = 80;
              };
            };
          }
        ];
        behavior = {
          scaleDown = {
            stabilizationWindowSeconds = 300;
            policies = [
              {
                type = "Percent";
                value = 50;
                periodSeconds = 60;
              }
            ];
          };
          scaleUp = {
            stabilizationWindowSeconds = 0;
            policies = [
              {
                type = "Percent";
                value = 100;
                periodSeconds = 30;
              }
              {
                type = "Pods";
                value = 1;
                periodSeconds = 30;
              }
            ];
            selectPolicy = "Max";
          };
        };
      };
    };

    # ── OpenCode Deployment (containerized) ──────────────────────
    # Replaces: 20-opencode-deployment.yaml, 20-opencode-multi-node.yaml,
    #           20-opencode-simple.yaml, 60-opencode-containerized.yaml
    Deployment.opencode = {
      metadata.labels = managed // {
        app = "opencode";
        component = "ai-coding-tool";
      };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "opencode";
        strategy = {
          type = "RollingUpdate";
          rollingUpdate = {
            maxSurge = 0;
            maxUnavailable = 1;
          };
        };
        template = {
          metadata = {
            labels = managed // {
              app = "opencode";
              component = "ai-coding-tool";
            };
            annotations = {
              "prometheus.io/scrape" = "true";
              "prometheus.io/port" = "9091";
              "prometheus.io/path" = "/metrics";
            };
          };
          spec = {
            nodeSelector."kubernetes.io/hostname" = "nexus";
            containers = {
              _namedlist = true;
              opencode = {
                image = "docker.io/reverb256/opencode:nixos";
                imagePullPolicy = "Always";
                command = [
                  "/bin/bash"
                  "-c"
                  ''
                    echo "OpenCode container ready"
                    tail -f /dev/null
                  ''
                ];
                env = {
                  _namedlist = true;
                  POD_NAME.valueFrom.fieldRef.fieldPath = "metadata.name";
                  HOME.value = "/home/j_kro";
                  USER.value = "j_kro";
                  OPENCODE_CONFIG_DIR.value = "/home/j_kro/.opencode";
                  PATH.value = "/home/j_kro/.nix-profile/bin:/bin:/usr/bin";
                };
                resources = {
                  requests = {
                    cpu = "500m";
                    memory = "512Mi";
                  };
                  limits = {
                    cpu = "2000m";
                    memory = "2Gi";
                  };
                };
                volumeMounts = {
                  _namedlist = true;
                  home-dir = {mountPath = "/home/j_kro";};
                };
                livenessProbe = {
                  exec.command = ["/bin/sh" "-c" "test -d /home/j_kro/.opencode"];
                  initialDelaySeconds = 10;
                  periodSeconds = 30;
                };
                readinessProbe = {
                  exec.command = ["/bin/sh" "-c" "test -d /home/j_kro/.opencode"];
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
                };
              };
              metrics = {
                image = "python:3.11-slim";
                command = [
                  "/bin/sh"
                  "-c"
                  ''
                    pip install prometheus_client psutil -q
                    python3 -c "
                    from prometheus_client import start_http_server, Gauge
                    import psutil, time
                    ACTIVE = Gauge('opencode_active_sessions', 'Active OpenCode sessions')
                    CPU_USAGE = Gauge('opencode_cpu_usage_percent', 'CPU usage percent')
                    start_http_server(9091)
                    while True:
                        ACTIVE.set(0)
                        CPU_USAGE.set(psutil.cpu_percent(interval=1))
                        time.sleep(10)
                    "
                  ''
                ];
                env = {
                  _namedlist = true;
                  HOME.value = "/home/j_kro";
                };
                ports = [
                  {
                    containerPort = 9091;
                    name = "metrics";
                    protocol = "TCP";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "50m";
                    memory = "64Mi";
                  };
                  limits = {
                    cpu = "100m";
                    memory = "128Mi";
                  };
                };
                volumeMounts = {
                  _namedlist = true;
                  home-dir = {
                    mountPath = "/home/j_kro";
                    readOnly = true;
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              home-dir.persistentVolumeClaim.claimName = "ai-coding-configs";
            };
            terminationGracePeriodSeconds = 30;
          };
        };
      };
    };

    # ── OpenCode HPA ─────────────────────────────────────────────
    # Replaces: 30-hpa.yaml (opencode-hpa portion), 60-opencode-containerized.yaml HPA
    HorizontalPodAutoscaler.opencode-hpa = {
      spec = {
        scaleTargetRef = {
          apiVersion = "apps/v1";
          kind = "Deployment";
          name = "opencode";
        };
        minReplicas = 1;
        maxReplicas = 4;
        metrics = [
          {
            type = "Resource";
            resource = {
              name = "cpu";
              target = {
                type = "Utilization";
                averageUtilization = 70;
              };
            };
          }
          {
            type = "Resource";
            resource = {
              name = "memory";
              target = {
                type = "Utilization";
                averageUtilization = 80;
              };
            };
          }
        ];
        behavior = {
          scaleDown = {
            stabilizationWindowSeconds = 300;
            policies = [
              {
                type = "Percent";
                value = 50;
                periodSeconds = 60;
              }
            ];
          };
          scaleUp = {
            stabilizationWindowSeconds = 0;
            policies = [
              {
                type = "Percent";
                value = 100;
                periodSeconds = 30;
              }
              {
                type = "Pods";
                value = 1;
                periodSeconds = 30;
              }
            ];
            selectPolicy = "Max";
          };
        };
      };
    };
  };
}

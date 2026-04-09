# Spacebot — AI agent for teams and communities (Discord/Telegram)
# Deployed on Nexus with persistent NFS storage
#
# Converted from: kubernetes-manifests/spacebot/
{
  pkgs,
  config,
  lib,
  ...
}:
{
  # ServiceMonitor is a CRD not in the default apiResources mapping
  config.kubernetes.apiMappings.ServiceMonitor = "monitoring.coreos.com/v1";

  config.kubernetes.objects = {
    # ── Namespace ──────────────────────────────────────────────
    none.Namespace.spacebot = {
      metadata.labels = {
        name = "spacebot";
        "pod-security.kubernetes.io/enforce" = "restricted";
        "pod-security.kubernetes.io/audit" = "restricted";
        "pod-security.kubernetes.io/warn" = "restricted";
      };
    };

    # ── ConfigMap ──────────────────────────────────────────────
    spacebot.ConfigMap.spacebot-config = {
      data."config.toml" = ''
        # Spacebot Configuration - Kubernetes-managed
        # LLM Provider - Using AI Gateway
        [llm.provider.ai-gateway]
        api_type = "openai_completions"
        base_url = "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080"
        api_key = "dummy-key-for-gateway"
        name = "AI Gateway"

        # Model Routing - Using gateway model names
        [defaults.routing]
        channel = "magnum-opus-35b-a3b-i1"
        worker = "magnum-opus-35b-a3b-i1"

        [defaults.routing.task_overrides]
        coding = "magnum-opus-35b-a3b-i1"

        # Agents
        [[agents]]
        id = "default"
        name = "Spacebot"
        description = "AI agent for teams and communities"

        # Messaging Platforms
        [messaging.telegram]
        token = "file:/run/agenix/spacebot-telegram-token"

        [[bindings]]
        agent_id = "default"
        channel = "telegram"

        # API Server
        [api]
        bind = "0.0.0.0"
        port = 19898

        # Database
        [database]
        path = "/data/spacebot.db"

        [secrets]
        path = "/data/secrets.redb"

        [memory.lance]
        path = "/data/lance"

        [ingestion]
        path = "/data/ingest"

        [skills]
        path = "/data/skills"
      '';
    };

    # ── Secret ─────────────────────────────────────────────────
    spacebot.Secret.spacebot-secrets = {
      type = "Opaque";
      stringData = {
        "telegram-token" = "PLACEHOLDER_FROM_AGENIX";
        "zai-coding-plan-key" = "";
        "kilo-api-key" = "";
      };
    };

    # ── PersistentVolume (cluster-scoped) ──────────────────────
    none.PersistentVolume.spacebot-data-nexus-pv = {
      spec = {
        capacity.storage = "10Gi";
        accessModes = [ "ReadWriteOnce" ];
        persistentVolumeReclaimPolicy = "Retain";
        storageClassName = "fast-local-ssd";
        local.path = "/mnt/nixos-share/spacebot-data";
        nodeAffinity.required.nodeSelectorTerms = [
          {
            matchExpressions = [
              {
                key = "kubernetes.io/hostname";
                operator = "In";
                values = [ "nexus" ];
              }
            ];
          }
        ];
      };
    };

    # ── PersistentVolumeClaim ──────────────────────────────────
    spacebot.PersistentVolumeClaim.spacebot-data = {
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        storageClassName = "fast-local-ssd";
        resources.requests.storage = "10Gi";
      };
    };

    # ── Deployment ─────────────────────────────────────────────
    spacebot.Deployment.spacebot = {
      metadata = {
        labels.app = "spacebot";
        annotations = {
          "prometheus.io/scrape" = "true";
          "prometheus.io/port" = "19898";
          "prometheus.io/path" = "/metrics";
        };
      };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 3;
        selector.matchLabels.app = "spacebot";
        strategy = {
          type = "RollingUpdate";
          rollingUpdate = {
            maxSurge = 0;
            maxUnavailable = 1;
          };
        };
        template = {
          metadata = {
            labels.app = "spacebot";
            annotations = {
              "prometheus.io/scrape" = "true";
              "prometheus.io/port" = "19898";
              "prometheus.io/path" = "/metrics";
            };
          };
          spec = {
            nodeSelector."kubernetes.io/hostname" = "nexus";
            schedulerName = "default-scheduler";
            priorityClassName = "system-cluster-critical";
            securityContext = {
              runAsNonRoot = false;
              fsGroup = 1000;
              seccompProfile.type = "RuntimeDefault";
            };
            dnsPolicy = "ClusterFirst";
            terminationGracePeriodSeconds = 30;
            containers = {
              _namedlist = true;
              spacebot = {
                image = "ghcr.io/spacedriveapp/spacebot:latest";
                imagePullPolicy = "Always";
                command = [
                  "spacebot"
                  "start"
                  "--config"
                  "/data/config.toml"
                ];
                ports = {
                  _namedlist = true;
                  http = {
                    containerPort = 19898;
                    protocol = "TCP";
                  };
                };
                env = {
                  _namedlist = true;
                  SPACEBOT_DATA_DIR.value = "/data";
                  OLLAMA_BASE_URL.value =
                    "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080";
                  ZAI_CODING_PLAN_KEY.valueFrom.secretKeyRef = {
                    name = "spacebot-secrets";
                    key = "zai-coding-plan-key";
                    optional = true;
                  };
                  KILO_API_KEY.valueFrom.secretKeyRef = {
                    name = "spacebot-secrets";
                    key = "kilo-api-key";
                    optional = true;
                  };
                  TELEGRAM_BOT_TOKEN.valueFrom.secretKeyRef = {
                    name = "spacebot-secrets";
                    key = "telegram-token";
                  };
                };
                resources = {
                  requests = {
                    cpu = "500m";
                    memory = "2Gi";
                  };
                  limits = {
                    cpu = "2";
                    memory = "4Gi";
                  };
                };
                livenessProbe = {
                  httpGet = {
                    path = "/api/health";
                    port = 19898;
                  };
                  initialDelaySeconds = 30;
                  periodSeconds = 10;
                  timeoutSeconds = 5;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/api/health";
                    port = 19898;
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 5;
                  timeoutSeconds = 3;
                  failureThreshold = 3;
                };
                volumeMounts = {
                  _namedlist = true;
                  data = {
                    mountPath = "/data";
                  };
                  config = {
                    mountPath = "/data/config.toml";
                    subPath = "config.toml";
                  };
                  "agenix-secrets" = {
                    mountPath = "/run/agenix";
                    readOnly = true;
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              data = {
                persistentVolumeClaim.claimName = "spacebot-data";
              };
              config = {
                configMap.name = "spacebot-config";
              };
              "agenix-secrets" = {
                hostPath = {
                  path = "/run/agenix";
                  type = "DirectoryOrCreate";
                };
              };
            };
          };
        };
      };
    };

    # ── Service ────────────────────────────────────────────────
    spacebot.Service.spacebot = {
      metadata.labels.app = "spacebot";
      spec = {
        type = "ClusterIP";
        ports = {
          _namedlist = true;
          http = {
            port = 19898;
            targetPort = 19898;
            protocol = "TCP";
          };
        };
        selector.app = "spacebot";
      };
    };

    # ── Ingress ────────────────────────────────────────────────
    spacebot.Ingress.spacebot = {
      metadata.annotations = {
        "ingress.caddy.lblt.net/profile" = "off";
        "ingress.caddy.lblt.net/scheme" = "https";
      };
      spec = {
        ingressClassName = "caddy";
        rules = [
          {
            host = "spacebot.cluster.local";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "spacebot";
                  port.number = 19898;
                };
              }
            ];
          }
        ];
      };
    };

    # ── ServiceMonitor ─────────────────────────────────────────
    spacebot.ServiceMonitor.spacebot = {
      metadata.labels.app = "spacebot";
      spec = {
        selector.matchLabels.app = "spacebot";
        endpoints = [
          {
            port = "http";
            path = "/metrics";
            interval = "30s";
            scrapeTimeout = "10s";
          }
        ];
      };
    };
  };
}

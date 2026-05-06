{...}: let
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };

  scratchImage = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
in {
  config.kubernetes.objects = {
    # ── Namespace ─────────────────────────────────────────────────
    # Privileged PSS required for hostPath mounts (scratch container pattern)
    none.Namespace.mcp = {
      metadata.labels =
        managed
        // {
          name = "mcp";
          "pod-security.kubernetes.io/enforce" = "privileged";
          "pod-security.kubernetes.io/audit" = "restricted";
          "pod-security.kubernetes.io/warn" = "restricted";
        };
    };

    # ── NetworkPolicy: default-deny-all ─────────────────────────
    mcp.NetworkPolicy.default-deny-all = {
      spec = {
        podSelector = {};
        policyTypes = ["Ingress" "Egress"];
      };
    };

    # ── Grafana MCP Server ────────────────────────────────────────
    # Binary: gh release download v0.13.1 -R grafana/mcp-grafana
    # Installed at /opt/mcp-servers/grafana-mcp on nexus
    # Exposes SSE on :8000, connects to Grafana in monitoring namespace
    mcp = {
      Deployment.grafana-mcp = {
        metadata.labels =
          managed
          // {app = "grafana-mcp";};
        spec = {
          replicas = 1;
          revisionHistoryLimit = 2;
          strategy.type = "Recreate";
          selector.matchLabels.app = "grafana-mcp";
          template = {
            metadata.labels.app = "grafana-mcp";
            spec = {
              nodeName = "nexus";
              containers = {
                _namedlist = true;
                grafana-mcp = {
                  image = scratchImage;
                  imagePullPolicy = "IfNotPresent";
                  command = ["/host-bin/grafana-mcp"];
                  args = ["--transport" "sse" "--address" "0.0.0.0:8000"];
                  ports = {
                    _namedlist = true;
                    http.containerPort = 8000;
                  };
                  env = {
                    GRAFANA_URL.name = "GRAFANA_URL";
                    GRAFANA_URL.value = "http://grafana.monitoring.svc.cluster.local:3000";
                    GRAFANA_USERNAME.name = "GRAFANA_USERNAME";
                    GRAFANA_USERNAME.value = "admin";
                    GRAFANA_PASSWORD.name = "GRAFANA_PASSWORD";
                    GRAFANA_PASSWORD.value = "admin";
                  };
                  volumeMounts = {
                    _namedlist = true;
                    host-bin.mountPath = "/host-bin";
                  };
                  resources = {
                    requests = {
                      cpu = "100m";
                      memory = "128Mi";
                    };
                    limits = {
                      cpu = "500m";
                      memory = "256Mi";
                    };
                  };
                };
              };
              volumes = {
                _namedlist = true;
                host-bin.hostPath = {
                  path = "/opt/mcp-servers";
                  type = "Directory";
                };
              };
            };
          };
        };
      };

      Service.grafana-mcp = {
        metadata.labels =
          managed
          // {app = "grafana-mcp";};
        spec = {
          selector.app = "grafana-mcp";
          ports = {
            _namedlist = true;
            http = {
              port = 8000;
              targetPort = 8000;
            };
          };
        };
      };

      # ── Qdrant MCP Server ────────────────────────────────────────
      # Pre-built image: docker build on nexus with pip install mcp-server-qdrant
      # Image: localhost/qdrant-mcp:latest (imported into k3s on nexus)
      # Exposes SSE on :8000, connects to Qdrant in ai-inference namespace
      Deployment.qdrant-mcp = {
        metadata.labels =
          managed
          // {app = "qdrant-mcp";};
        spec = {
          replicas = 1;
          revisionHistoryLimit = 2;
          strategy.type = "Recreate";
          selector.matchLabels.app = "qdrant-mcp";
          template = {
            metadata.labels.app = "qdrant-mcp";
            spec = {
              nodeName = "nexus";
              containers = {
                _namedlist = true;
                qdrant-mcp = {
                  image = "localhost/qdrant-mcp:latest";
                  imagePullPolicy = "Never";
                  command = ["/usr/local/bin/mcp-server-qdrant"];
                  args = ["--transport" "sse"];
                  ports = {
                    _namedlist = true;
                    http.containerPort = 8000;
                  };
                  env = {
                    QDRANT_URL.name = "QDRANT_URL";
                    QDRANT_URL.value = "http://qdrant.ai-inference.svc.cluster.local:6333";
                    EMBEDDING_PROVIDER.name = "EMBEDDING_PROVIDER";
                    EMBEDDING_PROVIDER.value = "fastembed";
                    EMBEDDING_MODEL.name = "EMBEDDING_MODEL";
                    EMBEDDING_MODEL.value = "sentence-transformers/all-MiniLM-L6-v2";
                    HOME.name = "HOME";
                    HOME.value = "/tmp";
                  };
                  resources = {
                    requests = {
                      cpu = "200m";
                      memory = "512Mi";
                    };
                    limits = {
                      cpu = "1000m";
                      memory = "1Gi";
                    };
                  };
                };
              };
            };
          };
        };
      };

      Service.qdrant-mcp = {
        metadata.labels =
          managed
          // {app = "qdrant-mcp";};
        spec = {
          selector.app = "qdrant-mcp";
          ports = {
            _namedlist = true;
            http = {
              port = 8000;
              targetPort = 8000;
            };
          };
        };
      };
    };
  };
}

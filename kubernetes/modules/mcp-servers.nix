{nexusPreferredAffinity, ...}: let
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };

  scratchImage = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
in {
  config = {
    kubernetes.objects = {
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
          policyTypes = [
            "Ingress"
            "Egress"
          ];
        };
      };

      # ── Grafana MCP Server ────────────────────────────────────────
      # Binary: gh release download v0.13.1 -R grafana/mcp-grafana
      # Installed at /opt/mcp-servers/grafana-mcp on nexus
      # Exposes SSE on :8000, connects to Grafana in monitoring namespace
      mcp.Deployment.grafana-mcp = {
        metadata.labels =
          managed
          // {
            app = "grafana-mcp";
          };
        spec = {
          replicas = 1;
          revisionHistoryLimit = 2;
          strategy.type = "Recreate";
          selector.matchLabels.app = "grafana-mcp";
          template = {
            metadata.labels.app = "grafana-mcp";
            spec = {
              securityContext = {
                runAsNonRoot = true;
                runAsUser = 1000;
                fsGroup = 1000;
              };
              affinity = nexusPreferredAffinity; # HA: prefer nexus, failover to sentry
              containers = {
                _namedlist = true;
                grafana-mcp = {
                  image = scratchImage;
                  imagePullPolicy = "IfNotPresent";
                  command = ["/host-bin/grafana-mcp"];
                  args = [
                    "--transport"
                    "sse"
                    "--address"
                    "0.0.0.0:8000"
                  ];
                  ports = {
                    _namedlist = true;
                    http.containerPort = 8000;
                  };
                  # NOTE: grafana-admin-secret must exist in 'mcp' namespace
                  # Populated by kubectl-apply-k8s-secrets from sops-nix (monitoring/grafana-admin-secret)
                  env = {
                    GRAFANA_URL.name = "GRAFANA_URL";
                    GRAFANA_URL.value = "http://grafana.monitoring.svc.cluster.local:3000";
                    GRAFANA_USERNAME.name = "GRAFANA_USERNAME";
                    GRAFANA_USERNAME.valueFrom.secretKeyRef = {
                      name = "grafana-admin-secret";
                      key = "admin-user";
                    };
                    GRAFANA_PASSWORD.name = "GRAFANA_PASSWORD";
                    GRAFANA_PASSWORD.valueFrom.secretKeyRef = {
                      name = "grafana-admin-secret";
                      key = "admin-password";
                    };
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
                    securityContext = {
                      allowPrivilegeEscalation = false;
                      capabilities.drop = ["ALL"];
                      seccompProfile.type = "RuntimeDefault";
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

      mcp.Service.grafana-mcp = {
        metadata.labels =
          managed
          // {
            app = "grafana-mcp";
          };
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
      mcp.Deployment.qdrant-mcp = {
        metadata.labels =
          managed
          // {
            app = "qdrant-mcp";
          };
        spec = {
          replicas = 1;
          revisionHistoryLimit = 2;
          strategy.type = "Recreate";
          selector.matchLabels.app = "qdrant-mcp";
          template = {
            metadata.labels.app = "qdrant-mcp";
            spec = {
              securityContext = {
                runAsNonRoot = true;
                runAsUser = 1000;
                fsGroup = 1000;
              };
              affinity = nexusPreferredAffinity; # HA: prefer nexus, failover to sentry
              containers = {
                _namedlist = true;
                qdrant-mcp = {
                  image = "localhost/qdrant-mcp:v1.0.0"; # Local build (imported into k3s on nexus)
                  imagePullPolicy = "Never";
                  command = ["/usr/local/bin/mcp-server-qdrant"];
                  args = [
                    "--transport"
                    "sse"
                  ];
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
                  securityContext = {
                    allowPrivilegeEscalation = false;
                    capabilities.drop = ["ALL"];
                    runAsNonRoot = true;
                    runAsUser = 1000;
                    seccompProfile.type = "RuntimeDefault";
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
                    securityContext = {
                      allowPrivilegeEscalation = false;
                      capabilities.drop = ["ALL"];
                      seccompProfile.type = "RuntimeDefault";
                    };
                  };
                };
              };
            };
          };
        };
      };

      mcp.Service.qdrant-mcp = {
        metadata.labels =
          managed
          // {
            app = "qdrant-mcp";
          };
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

      # ── Toolhive MCPServer: kb-mcp (kubernetes-mcp-server) ────────────
      # NOTE: Commented out - easykubenix doesn't support toolhive API yet
      # Apply manually: kubectl apply -f kubernetes-manifests/mcp/kb-mcp.yaml
      # toolhive.stacklok.dev.MCPServer.kb-mcp = {
      #   metadata.labels = managed // {
      #     app = "kb-mcp";
      #     "app.kubernetes.io/component" = "mcp-server";
      #   };
      #   spec = {
      #     image = "ghcr.io/containers/kubernetes-mcp-server:latest-linux-amd64";
      #     transport = "stdio";
      #     proxyMode = "streamable-http";
      #     proxyPort = 8080;
      #     env = [
      #       { name = "QDRANT_HOST"; value = "qdrant.ai-inference.svc.cluster.local"; }
      #       { name = "QDRANT_PORT"; value = "6333"; }
      #       { name = "KB_COLLECTION"; value = "knowledge_base"; }
      #       { name = "KB_MODEL"; value = "all-MiniLM-L6-v2"; }
      #       { name = "HOME"; value = "/tmp"; }
      #     ];
      #     resources = {
      #       limits = { cpu = "1"; memory = "2Gi"; };
      #       requests = { cpu = "200m"; memory = "512Mi"; };
      #     };
      #     sessionAffinity = "ClientIP";
      #     trustProxyHeaders = false;
      #   };
      # };

      # ── Toolhive Operator ────────────────────────────────────────
      # Manages MCP server runner pods via CRDs.
      # CRDs + RBAC: kubernetes/static-manifests/toolhive-crds.yaml + toolhive-rbac.yaml
      mcp.Deployment.toolhive-operator = {
        metadata.labels =
          managed
          // {
            app = "toolhive-operator";
            "app.kubernetes.io/name" = "toolhive-operator";
            "app.kubernetes.io/component" = "operator";
          };
        spec = {
          replicas = 1;
          revisionHistoryLimit = 2;
          selector.matchLabels.app = "toolhive-operator";
          strategy.type = "Recreate";
          template = {
            metadata.labels.app = "toolhive-operator";
            spec = {
              serviceAccountName = "toolhive-operator";
              nodeSelector."kubernetes.io/hostname" = "nexus";
              containers = [
                {
                  name = "toolhive-operator";
                  image = "ghcr.io/stacklok/toolhive/operator:v0.27.0";
                  args = ["--leader-elect"];
                  env = {
                    POD_NAMESPACE.valueFrom.fieldRef.fieldPath = "metadata.namespace";
                    GOMEMLIMIT = "110MiB";
                    GOGC = "75";
                    UNSTRUCTURED_LOGS = "false";
                    TOOLHIVE_USE_CONFIGMAP = "true";
                    ENABLE_EXPERIMENTAL_FEATURES = "false";
                    ENABLE_SERVER = "true";
                    ENABLE_REGISTRY = "true";
                    ENABLE_VMCP = "false";
                    WATCH_NAMESPACE = "mcp";
                    TOOLHIVE_RUNNER_IMAGE = "ghcr.io/stacklok/toolhive/proxyrunner:v0.27.0";
                    VMCP_IMAGE = "ghcr.io/stacklok/toolhive/vmcp:v0.27.0";
                    TOOLHIVE_PROXY_HOST = "0.0.0.0";
                    TOOLHIVE_REGISTRY_API_IMAGE = "ghcr.io/stacklok/thv-registry-api:v1.3.0";
                  };
                  ports = [
                    {
                      name = "metrics";
                      containerPort = 8080;
                      protocol = "TCP";
                    }
                    {
                      name = "health";
                      containerPort = 8081;
                      protocol = "TCP";
                    }
                  ];
                  resources = {
                    requests = {
                      cpu = "50m";
                      memory = "64Mi";
                    };
                    limits = {
                      cpu = "200m";
                      memory = "128Mi";
                    };
                  };
                }
              ];
            };
          };
        };
      };

      mcp.Service.toolhive-operator = {
        metadata.labels =
          managed
          // {
            app = "toolhive-operator";
            "app.kubernetes.io/name" = "toolhive-operator";
          };
        spec = {
          selector.app = "toolhive-operator";
          ports = {
            _namedlist = true;
            metrics = {
              port = 8080;
              targetPort = 8080;
            };
            health = {
              port = 8081;
              targetPort = 8081;
            };
          };
        };
      };

      mcp.ServiceAccount.toolhive-operator = {
        metadata.labels =
          managed
          // {
            app = "toolhive-operator";
            "app.kubernetes.io/name" = "toolhive-operator";
          };
      };

      # ── C5: NetworkPolicy per MCP server ────────────────────────────────
      # Allow ingress to MCP SSE endpoints from ingress-system and cluster subnet
      mcp.NetworkPolicy.allow-mcp-sse-ingress = {
        metadata.labels = managed;
        spec = {
          podSelector.matchLabels."app.kubernetes.io/component" = "mcp-server";
          policyTypes = ["Ingress"];
          ingress = [
            {
              from = [
                {namespaceSelector.matchLabels.name = "ingress-system";}
                {ipBlock.cidr = "10.1.1.0/24";}
              ];
              ports = [
                {
                  protocol = "TCP";
                  port = 8000;
                } # grafana-mcp, qdrant-mcp
                {
                  protocol = "TCP";
                  port = 8080;
                } # kubernetes-mcp
                {
                  protocol = "TCP";
                  port = 9001;
                } # searxng-mcp
                {
                  protocol = "TCP";
                  port = 9003;
                } # lightpanda-mcp
                {
                  protocol = "TCP";
                  port = 9004;
                } # nixos-cluster-mcp
                {
                  protocol = "TCP";
                  port = 9005;
                } # casdoor-mcp
              ];
            }
          ];
        };
      };

      # Allow MCP servers egress to DNS and cluster services
      mcp.NetworkPolicy.allow-mcp-egress = {
        metadata.labels = managed;
        spec = {
          podSelector.matchLabels."app.kubernetes.io/component" = "mcp-server";
          policyTypes = ["Egress"];
          egress = [
            {
              to = [];
              ports = [
                {
                  protocol = "UDP";
                  port = 53;
                }
                {
                  protocol = "TCP";
                  port = 53;
                }
                {
                  protocol = "TCP";
                  port = 443;
                }
                {
                  protocol = "TCP";
                  port = 80;
                }
                {
                  protocol = "TCP";
                  port = 6443;
                } # K8s API
              ];
            }
          ];
        };
      };
    };

  }; # close config
}

{
  cluster,
  nexusPreferredAffinity,
  ...
}: let
  labels = {
    app = "vane";
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
in {
  config.kubernetes.objects = {
    # ── Vane Service (AI search synthesis) ─────────────────────────
    ai-inference.Deployment.vane = {
      metadata = {inherit labels;};
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        strategy.rollingUpdate.maxSurge = 0;
        selector.matchLabels = labels;
        template = {
          metadata.labels = labels;
          spec = {
            nodeName = "nexus";
            containers = [
              {
                name = "vane";
                image = "ghcr.io/reverb256/vane:latest";
                imagePullPolicy = "IfNotPresent";
                ports = [
                  {
                    containerPort = 3000;
                    name = "http";
                    protocol = "TCP";
                  }
                ];
                env = [
                  {
                    name = "GATEWAY_URL";
                    value = "http://ai-gateway.ai-inference.svc.cluster.local:8080";
                  }
                  {
                    name = "SEARXNG_URL";
                    value = "http://searxng.search.svc.cluster.local:8080";
                  }
                  {
                    name = "CROSS_ENCODER_DEVICE";
                    value = "cpu";
                  }
                  {
                    name = "PORT";
                    value = "3000";
                  }
                  {
                    name = "LOG_LEVEL";
                    value = "info";
                  }
                  {
                    name = "HOSTNAME";
                    value = "0.0.0.0";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "500m";
                    memory = "512Mi";
                  };
                  limits = {
                    cpu = "2";
                    memory = "2Gi";
                  };
                };
                livenessProbe = {
                  httpGet = {
                    path = "/health";
                    port = 3000;
                  };
                  initialDelaySeconds = 30;
                  periodSeconds = 15;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/health";
                    port = 3000;
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 10;
                };
              }
            ];
          };
        };
      };
    };

    ai-inference.Service.vane = {
      metadata.labels = labels;
      spec = {
        selector = labels;
        ports = [
          {
            name = "http";
            port = 3000;
            targetPort = 3000;
            protocol = "TCP";
          }
        ];
      };
    };

    # ── Fusion Service (RRF reranking + query routing) ────────────
    ai-inference.Deployment.fusion = {
      metadata = {
        labels = {
          app = "fusion";
          "app.kubernetes.io/managed-by" = "easykubenix";
        };
      };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels = {app = "fusion";};
        template = {
          metadata.labels = {app = "fusion";};
          spec = {
            nodeName = "nexus";
            containers = [
              {
                name = "fusion";
                image = "python:3.11-slim";
                imagePullPolicy = "IfNotPresent";
                ports = [
                  {
                    containerPort = 8085;
                    name = "http";
                  }
                ];
                env = [
                  {
                    name = "KF_API_URL";
                    value = "http://knowledge-fabric.ai-inference.svc.cluster.local:3100";
                  }
                  {
                    name = "SEARXNG_URL";
                    value = "http://searxng.search.svc.cluster.local:8080";
                  }
                  {
                    name = "GATEWAY_URL";
                    value = "http://ai-gateway.ai-inference.svc.cluster.local:8080";
                  }
                  {
                    name = "PORT";
                    value = "8085";
                  }
                ];
                resources = {
                  requests = {
                    cpu = "200m";
                    memory = "256Mi";
                  };
                  limits = {
                    cpu = "1";
                    memory = "1Gi";
                  };
                };
                livenessProbe = {
                  httpGet = {
                    path = "/health";
                    port = 8085;
                  };
                  initialDelaySeconds = 30;
                };
              }
            ];
          };
        };
      };
    };

    ai-inference.Service.fusion = {
      metadata.labels = {app = "fusion";};
      spec = {
        selector = {app = "fusion";};
        ports = [
          {
            name = "http";
            port = 8085;
            targetPort = 8085;
            protocol = "TCP";
          }
        ];
      };
    };
  };
}
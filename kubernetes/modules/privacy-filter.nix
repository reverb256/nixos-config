{
  pkgs,
  config,
  lib,
  ...
}: let
  # Privacy filter image - using the package we already have
  # The package builds a Python FastAPI server that runs on port 8081
  privacyFilterImage = "docker.io/python:3.12-slim";

  # Target nexus for GPU acceleration (46GB RAM, RTX 4060 Ti)
  targetNode = "nexus";

  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
in {
  config.kubernetes.objects = {
    # ── Namespace ──────────────────────────────────────────────────────
    none.Namespace.privacy-filter = {
      metadata.labels =
        managed
        // {
          name = "privacy-filter";
          "pod-security.kubernetes.io/enforce" = "baseline";
          "pod-security.kubernetes.io/audit" = "restricted";
          "pod-security.kubernetes.io/warn" = "restricted";
          "app.kubernetes.io/part-of" = "ai-inference";
        };
    };

    # ── Deployment ─────────────────────────────────────────────────────
    privacy-filter.Deployment.privacy-filter = {
      metadata.labels =
        managed
        // {
          app = "privacy-filter";
          "app.kubernetes.io/part-of" = "ai-inference";
        };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "privacy-filter";
        strategy = {
          type = "RollingUpdate";
          rollingUpdate.maxSurge = 0;
          rollingUpdate.maxUnavailable = 1;
        };
        template = {
          metadata.labels = managed // {app = "privacy-filter";};
          spec = {
            nodeName = targetNode;
            automountServiceAccountToken = false;
            terminationGracePeriodSeconds = 30;
            securityContext = {
              runAsNonRoot = true;
              runAsUser = 1000;
              runAsGroup = 1000;
              fsGroup = 1000;
              seccompProfile.type = "RuntimeDefault";
            };
            containers = {
              _namedlist = true;
              privacy-filter = {
                image = privacyFilterImage;
                imagePullPolicy = "IfNotPresent";
                command = [
                  "/bin/bash"
                  "-c"
                  ''
                    pip install fastapi uvicorn transformers torch accelerate safetensors pydantic
                    ${pkgs.privacy-filter}/bin/privacy-filter-server
                  ''
                ];
                ports = {
                  _namedlist = true;
                  http = {
                    containerPort = 8081;
                    protocol = "TCP";
                  };
                };
                env = {
                  _namedlist = true;
                  PORT.value = "8081";
                  MODEL_DEVICE.value = "cuda";
                };
                resources = {
                  requests = {
                    cpu = "500m";
                    memory = "2Gi";
                    "nvidia.com/gpu" = "0";
                  };
                  limits = {
                    cpu = "4000m";
                    memory = "8Gi";
                    "nvidia.com/gpu" = "1";
                  };
                };
                livenessProbe = {
                  exec.command = ["/bin/bash" "-c" "curl -f http://localhost:8081/health || exit 1"];
                  initialDelaySeconds = 60;
                  periodSeconds = 30;
                  timeoutSeconds = 10;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  httpGet.path = "/health";
                  port = 8081;
                  initialDelaySeconds = 30;
                  periodSeconds = 10;
                  timeoutSeconds = 5;
                  failureThreshold = 3;
                };
                securityContext = {
                  allowPrivilegeEscalation = false;
                  readOnlyRootFilesystem = false;
                  capabilities.drop = ["ALL"];
                };
              };
            };
          };
        };
      };
    };

    # ── Service ─────────────────────────────────────────────────────────
    privacy-filter.Service.privacy-filter = {
      spec = {
        selector.app = "privacy-filter";
        ports = [
          {
            name = "http";
            port = 8080;
            targetPort = "http";
            protocol = "TCP";
          }
        ];
        type = "ClusterIP";
      };
    };

    # ── NetworkPolicy: default-deny-all ─────────────────────────────────
    privacy-filter.NetworkPolicy.default-deny-all = {
      spec = {
        podSelector = {};
        policyTypes = ["Ingress" "Egress"];
      };
    };

    # ── NetworkPolicy: allow rules ────────────────────────────────────────────
    # Allow ingress from AI gateway (ai-inference namespace) and monitoring
    privacy-filter.NetworkPolicy.privacy-filter-allow = {
      spec = {
        podSelector.matchLabels.app = "privacy-filter";
        policyTypes = ["Ingress" "Egress"];
        ingress = [
          {
            from = [
              {namespaceSelector.matchLabels.name = "ai-inference";}
              {namespaceSelector.matchLabels.name = "ingress-system";}
            ];
          }
        ];
        egress = [
          {
            to = [
              {
                namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "kube-system";
              }
            ];
            ports = [
              {
                protocol = "TCP";
                port = 53;
              }
              {
                protocol = "UDP";
                port = 53;
              }
            ];
          }
        ];
      };
    };
  };
}

{
  config,
  lib,
  ...
}: let
  havenImage = "nexus:5000/mosiac:v0.1.6-forum";
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };
in {
  config.kubernetes.objects = {
    none.Namespace.haven = {
      metadata.labels =
        managed
        // {
          name = "haven";
          "pod-security.kubernetes.io/enforce" = "privileged";
          "pod-security.kubernetes.io/audit" = "restricted";
          "pod-security.kubernetes.io/warn" = "restricted";
        };
    };

    none.PersistentVolume.haven-data-nexus-pv = {
      spec = {
        capacity.storage = "5Gi";
        accessModes = ["ReadWriteOnce"];
        persistentVolumeReclaimPolicy = "Retain";
        storageClassName = "fast-local-ssd";
        local.path = "/mnt/nixos-share/haven-data";
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

    haven.PersistentVolumeClaim.haven-data = {
      spec = {
        accessModes = ["ReadWriteOnce"];
        storageClassName = "fast-local-ssd";
        resources.requests.storage = "5Gi";
      };
    };

    haven.Deployment.haven = {
      metadata.labels = managed // {app = "haven";};
      spec = {
        replicas = 1;
        revisionHistoryLimit = 3;
        selector.matchLabels.app = "haven";
        strategy = {
          type = "RollingUpdate";
          rollingUpdate = {
            maxSurge = 0;
            maxUnavailable = 1;
          };
        };
        template = {
          metadata.labels = managed // {app = "haven";};
          spec = {
            nodeSelector."kubernetes.io/hostname" = "nexus";
            schedulerName = "default-scheduler";
            securityContext = {
              runAsNonRoot = false;
              fsGroup = 1000;
              seccompProfile.type = "RuntimeDefault";
            };
            terminationGracePeriodSeconds = 30;
            containers = {
              _namedlist = true;
              haven = {
                image = havenImage;
                imagePullPolicy = "IfNotPresent";
                ports = {
                  _namedlist = true;
                  https = {
                    containerPort = 3000;
                    protocol = "TCP";
                  };
                  http-redirect = {
                    containerPort = 3001;
                    protocol = "TCP";
                  };
                };
                lifecycle = {
                  postStart = {
                    exec = {
                      command = ["sh" "-c" "sed -i s/const maxAttempts = 20;/const maxAttempts = 200;/ /app/src/auth.js 2>/dev/null; sed -i s/const maxAttempts = 5;/const maxAttempts = 50;/ /app/src/auth.js 2>/dev/null; exit 0"];
                    };
                  };
                };
                env = {
                  _namedlist = true;
                  PORT.value = "3000";
                  HOST.value = "0.0.0.0";
                  HAVEN_DATA_DIR.value = "/data";
                  NODE_ENV.value = "production";
                  FORCE_HTTP.value = "true";
                  MOSIAC_RP_ID.value = "10.1.1.120";
                  MOSIAC_ORIGIN.value = "http://10.1.1.120:32100";
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
                livenessProbe = {
                  httpGet = {
                    path = "/api/health";
                    port = 3000;
                  };
                  initialDelaySeconds = 15;
                  periodSeconds = 30;
                  timeoutSeconds = 5;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/api/health";
                    port = 3000;
                  };
                  initialDelaySeconds = 10;
                  periodSeconds = 10;
                  timeoutSeconds = 3;
                  failureThreshold = 3;
                };
                volumeMounts = {
                  _namedlist = true;
                  data = {
                    mountPath = "/data";
                  };
                };
              };
              # Sidecar removed: auth handled by Caddy forward_auth → central-auth
            };
            volumes = {
              _namedlist = true;
              data = {
                persistentVolumeClaim.claimName = "haven-data";
              };
            };
          };
        };
      };
    };

    haven.Service.haven = {
      metadata.labels = managed // {app = "haven";};
      spec = {
        type = "NodePort";
        ports = {
          _namedlist = true;
          http = {
            port = 3000;
            targetPort = 3000;
            nodePort = 32100;
            protocol = "TCP";
          };
        };
        selector.app = "haven";
      };
    };

    haven.NetworkPolicy.default-deny-all = {
      spec = {
        podSelector = {};
        policyTypes = ["Ingress" "Egress"];
      };
    };

    haven.NetworkPolicy.allow-haven-ingress = {
      metadata.labels =
        managed
        // {
          app = "haven";
          policy = "allow-ingress";
        };
      spec = {
        podSelector.matchLabels.app = "haven";
        policyTypes = ["Ingress"];
        ingress = [
          {
            from = [
              {ipBlock.cidr = "10.1.1.0/24";}
              
              {namespaceSelector.matchLabels.name = "ingress-system";}
            ];
            ports = [
              {
                protocol = "TCP";
                port = 3000;
              }
            ];
          }
        ];
      };
    };

    haven.NetworkPolicy.allow-haven-egress = {
      metadata.labels =
        managed
        // {
          app = "haven";
          policy = "allow-egress";
        };
      spec = {
        podSelector.matchLabels.app = "haven";
        policyTypes = ["Egress"];
        egress = [
          {
            to = [{ipBlock.cidr = "0.0.0.0/0";}];
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
                port = 80;
              }
              {
                protocol = "TCP";
                port = 443;
              }
            ];
          }
        ];
      };
    };
    haven.Ingress.haven = {
      metadata.labels = managed // {app = "haven";};
      spec = {
        ingressClassName = "caddy";
        rules = [
          {
            host = "haven.lan";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "haven";
                  port.number = 3000;
                };
              }
            ];

          }
        ];
      };
    };
  };
}

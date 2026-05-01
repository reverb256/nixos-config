{
  config,
  lib,
  ...
}: let
  havenImage = "ghcr.io/ancsemi/haven:3.1.1";
in {
  config.kubernetes.objects = {
    none.Namespace.haven = {
      metadata.labels = {
        name = "haven";
        "pod-security.kubernetes.io/enforce" = "baseline";
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

    haven.Secret.haven-oidc = {
      type = "Opaque";
      stringData = {
        client-id = "a2e029b7c29bc2912dc1";
        cookie-secret = "e7f2cb9404807a4e1e2be8ccad503775";
      };
    };

    haven.Deployment.haven = {
      metadata.labels.app = "haven";
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
          metadata.labels.app = "haven";
          spec = {
            nodeSelector."kubernetes.io/hostname" = "nexus";
            schedulerName = "default-scheduler";
            securityContext = {
              runAsNonRoot = false;
              fsGroup = 1000;
              seccompProfile.type = "RuntimeDefault";
            };
            hostNetwork = true;
            dnsPolicy = "ClusterFirstWithHostNet";
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
                env = {
                  _namedlist = true;
                  PORT.value = "3000";
                  HOST.value = "0.0.0.0";
                  HAVEN_DATA_DIR.value = "/data";
                  NODE_ENV.value = "production";
                  FORCE_HTTP.value = "true";
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
              oauth2-proxy = {
                image = "quay.io/oauth2-proxy/oauth2-proxy:v7.10.0";
                imagePullPolicy = "IfNotPresent";
                ports = [{
                  containerPort = 4180;
                  name = "http";
                  protocol = "TCP";
                }];
                env = {
                  OAUTH2_PROXY_PROVIDER.value = "oidc";
                  OAUTH2_PROXY_OIDC_ISSUER_URL.value = "https://auth.lan";
                  OAUTH2_PROXY_CLIENT_ID.valueFrom.secretKeyRef = { name = "haven-oidc"; key = "client-id"; };
                  OAUTH2_PROXY_CLIENT_SECRET.valueFrom.secretKeyRef = { name = "haven-oidc"; key = "client-secret"; };
                  OAUTH2_PROXY_COOKIE_SECRET.valueFrom.secretKeyRef = { name = "haven-oidc"; key = "cookie-secret"; };
                  OAUTH2_PROXY_REDIRECT_URL.value = "https://haven.lan/oauth2/callback";
                  OAUTH2_PROXY_UPSTREAM.value = "http://127.0.0.1:3000";
                  OAUTH2_PROXY_EMAIL_DOMAINS.value = "*";
                  OAUTH2_PROXY_PASS_AUTHORIZATION_HEADER.value = "true";
                  OAUTH2_PROXY_SET_AUTHORIZATION_HEADER.value = "true";
                  OAUTH2_PROXY_SKIP_JWT_BEARER_TOKENS.value = "true";
                  OAUTH2_PROXY_COOKIE_SECURE.value = "false";
                  OAUTH2_PROXY_COOKIE_SAMESITE.value = "lax";
                  OAUTH2_PROXY_INSECURE_OIDC_ALLOW_UNVERIFIED_EMAIL.value = "true";
                  OAUTH2_PROXY_OIDC_EMAIL_CLAIM.value = "sub";
                  OAUTH2_PROXY_SKIP_AUTH_REGEX.value = "^/api/health$";
                };
              };
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
      metadata.labels.app = "haven";
      spec = {
        type = "NodePort";
        ports = {
          _namedlist = true;
          http = {
            port = 3000;
            targetPort = 4180;
            nodePort = 32100;
            protocol = "TCP";
          };
        };
        selector.app = "haven";
      };
    };

    haven.NetworkPolicy.allow-haven-ingress = {
      metadata.labels = {
        app = "haven";
        policy = "allow-ingress";
      };
      spec = {
        podSelector.matchLabels.app = "haven";
        policyTypes = ["Ingress"];
        ingress = [
          {
            from = [
              {namespaceSelector.matchLabels.name = "ingress-system";}
            ];
            ports = [
              {
                protocol = "TCP";
                port = 4180;
              }
            ];
          }
        ];
      };
    };

    haven.NetworkPolicy.allow-haven-egress = {
      metadata.labels = {
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
            ];
          }
        ];
      };
    };
  };
}

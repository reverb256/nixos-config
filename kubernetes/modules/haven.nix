# Haven — Self-hosted Discord alternative
# https://github.com/ancsemi/Haven
#
# Deploys on Nexus with persistent NFS storage for SQLite data.
# Voice requires a TURN server (coturn) for NAT traversal — LAN-only
# voice works without it.
#
# Image: ghcr.io/ancsemi/haven (multi-arch amd64/arm64)
# Ports: 3000 (HTTPS), 3001 (HTTP→HTTPS redirect)
# Data:  /data (SQLite DB, .env, SSL certs, uploads)
{
  pkgs,
  config,
  lib,
  ...
}:
let
  havenImage = "ghcr.io/ancsemi/haven:2.9.7";
in
{
  config.kubernetes.objects = {
    # ── Namespace ──────────────────────────────────────────────
    none.Namespace.haven = {
      metadata.labels = {
        name = "haven";
        "pod-security.kubernetes.io/enforce" = "privileged";
        "pod-security.kubernetes.io/audit" = "restricted";
        "pod-security.kubernetes.io/warn" = "restricted";
      };
    };

    # ── PersistentVolume (cluster-scoped) ──────────────────────
    none.PersistentVolume.haven-data-nexus-pv = {
      spec = {
        capacity.storage = "5Gi";
        accessModes = [ "ReadWriteOnce" ];
        persistentVolumeReclaimPolicy = "Retain";
        storageClassName = "fast-local-ssd";
        local.path = "/mnt/nixos-share/haven-data";
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
    haven.PersistentVolumeClaim.haven-data = {
      spec = {
        accessModes = [ "ReadWriteOnce" ];
        storageClassName = "fast-local-ssd";
        resources.requests.storage = "5Gi";
      };
    };

    # ── Deployment ─────────────────────────────────────────────
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
                  # Disable built-in HTTPS — Caddy handles TLS termination
                  FORCE_HTTP.value = "true";
                };
                resources = {
                  requests = {
                    cpu = "250m";
                    memory = "256Mi";
                  };
                  limits = {
                    cpu = "1";
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

    # ── Service ────────────────────────────────────────────────
    haven.Service.haven = {
      metadata.labels.app = "haven";
      spec = {
        type = "ClusterIP";
        ports = {
          _namedlist = true;
          http = {
            port = 3000;
            targetPort = 3000;
            protocol = "TCP";
          };
        };
        selector.app = "haven";
      };
    };

    # ── NetworkPolicy: allow ingress from Caddy ────────────────
    haven.NetworkPolicy.allow-haven-ingress = {
      metadata.labels = {
        app = "haven";
        policy = "allow-ingress";
      };
      spec = {
        podSelector.matchLabels.app = "haven";
        policyTypes = [ "Ingress" ];
        ingress = [
          {
            from = [
              { namespaceSelector.matchLabels.name = "ingress-nginx"; }
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

    
    # ── Ingress ────────────────────────────────────────────────
    haven.Ingress.haven = {
      metadata.annotations = {
        "ingress.caddy.lblt.net/scheme" = "http";
      };
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
          {
            host = "haven.cluster.local";
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

    # ── NetworkPolicy: allow egress (DNS, outbound) ────────────
    haven.NetworkPolicy.allow-haven-egress = {
      metadata.labels = {
        app = "haven";
        policy = "allow-egress";
      };
      spec = {
        podSelector.matchLabels.app = "haven";
        policyTypes = [ "Egress" ];
        egress = [
          # DNS
          {
            to = [ { ipBlock.cidr = "0.0.0.0/0"; } ];
            ports = [
              { protocol = "UDP"; port = 53; }
              { protocol = "TCP"; port = 53; }
            ];
          }
        ];
      };
    };
  };
}

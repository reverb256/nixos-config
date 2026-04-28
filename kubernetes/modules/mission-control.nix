{
  pkgs,
  config,
  lib,
  ...
}:
let
  # Pinned to latest published GHCR tag (sha-90a5615, Apr 14 2026)
  # Latest commit a020d1b has failing CI, no published image yet.
  # Check: https://github.com/builderz-labs/mission-control/pkgs/container/mission-control/versions
  mcImage = "ghcr.io/builderz-labs/mission-control:sha-90a5615";

  # NFS server is zephyr (10.1.1.110).
  # NFS PV survives node failure if pod migrates (RWX access mode).
  nfsServer = "10.1.1.110";
  nfsDataPath = "/data/shared/mission-control-data";

  # Pod targets sentry -- 31GB RAM, not OOM-constrained like zephyr.
  # Nexus is down; sentry is the available workload node.
  targetNode = "sentry";
in
{
  config.kubernetes.objects = {
    # ── Namespace ──────────────────────────────────────────────────────
    none.Namespace.orchestration = {
      metadata.labels = {
        name = "orchestration";
        "pod-security.kubernetes.io/enforce" = "baseline";
        "pod-security.kubernetes.io/audit" = "restricted";
        "pod-security.kubernetes.io/warn" = "restricted";
        "app.kubernetes.io/part-of" = "personal-corporation";
      };
    };

    # ── NFS PersistentVolume (survives node loss) ──────────────────────
    none.PersistentVolume.mission-control-data-pv = {
      spec = {
        capacity.storage = "2Gi";
        accessModes = [ "ReadWriteMany" ];
        persistentVolumeReclaimPolicy = "Retain";
        storageClassName = "nfs";
        nfs = {
          server = nfsServer;
          path = nfsDataPath;
        };
      };
    };

    # ── PVC binding to NFS PV ──────────────────────────────────────────
    orchestration.PersistentVolumeClaim.mission-control-data = {
      spec = {
        accessModes = [ "ReadWriteMany" ];
        storageClassName = "nfs";
        resources.requests.storage = "2Gi";
      };
    };

    # ── Secret ─────────────────────────────────────────────────────────
    # TODO: migrate to agenix. Currently matches existing imperative secrets.
    orchestration.Secret.mission-control-secrets = {
      type = "Opaque";
      stringData = {
        auth-pass = "yt1x6F61dfy6R9jpW66q7zgOLdnbNSxW";
        api-key = "5MDMlvnW0gYdgZxk1y6PZSuULQRpIVxw0OxSPqZHm8o";
      };
    };

    # ── Deployment ─────────────────────────────────────────────────────
    orchestration.Deployment.mission-control = {
      metadata.labels = {
        app = "mission-control";
        "app.kubernetes.io/part-of" = "personal-corporation";
      };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 3;
        selector.matchLabels.app = "mission-control";
        strategy = {
          type = "Recreate";
        };
        template = {
          metadata.labels.app = "mission-control";
          spec = {
            nodeSelector."kubernetes.io/hostname" = targetNode;
            automountServiceAccountToken = false;
            terminationGracePeriodSeconds = 30;
            securityContext = {
              fsGroup = 1001;
              seccompProfile.type = "RuntimeDefault";
            };
            containers = {
              _namedlist = true;
              mission-control = {
                image = mcImage;
                imagePullPolicy = "IfNotPresent";
                ports = {
                  _namedlist = true;
                  http = {
                    containerPort = 3000;
                    protocol = "TCP";
                  };
                };
                env = {
                  _namedlist = true;
                  AUTH_USER.value = "admin";
                  AUTH_PASS.valueFrom.secretKeyRef = {
                    name = "mission-control-secrets";
                    key = "auth-pass";
                  };
                  API_KEY.valueFrom.secretKeyRef = {
                    name = "mission-control-secrets";
                    key = "api-key";
                  };
                  PORT.value = "3000";
                  NEXT_PUBLIC_GATEWAY_OPTIONAL.value = "true";
                  MC_ALLOWED_HOSTS.value = "mission-control.lan,mc.cluster.local,10.1.1.110,10.244.0.0/16,localhost,127.0.0.1";
                  MISSION_CONTROL_DATA_DIR.value = "/data";
                  SKIP_AUTH_FOR_PROBES.value = "true";
                };
                resources = {
                  requests = {
                    cpu = "250m";
                    memory = "512Mi";
                  };
                  limits = {
                    cpu = "2";
                    memory = "2Gi";
                  };
                };
                livenessProbe = {
                  httpGet = {
                    path = "/api/status?action=health";
                    port = 3000;
                  };
                  initialDelaySeconds = 30;
                  periodSeconds = 30;
                  timeoutSeconds = 10;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  httpGet = {
                    path = "/api/status?action=health";
                    port = 3000;
                  };
                  initialDelaySeconds = 15;
                  periodSeconds = 10;
                  timeoutSeconds = 5;
                  failureThreshold = 3;
                };
                startupProbe = {
                  httpGet = {
                    path = "/api/status?action=health";
                    port = 3000;
                  };
                  initialDelaySeconds = 5;
                  periodSeconds = 5;
                  failureThreshold = 12;
                };
                volumeMounts = {
                  _namedlist = true;
                  data = {
                    mountPath = "/data";
                  };
                  tmp = {
                    mountPath = "/tmp";
                  };
                };
              };
            };
            volumes = {
              _namedlist = true;
              data = {
                persistentVolumeClaim.claimName = "mission-control-data";
              };
              tmp = {
                emptyDir = { };
              };
            };
          };
        };
      };
    };

    # ── Service ────────────────────────────────────────────────────────
    orchestration.Service.mission-control = {
      metadata.labels.app = "mission-control";
      spec = {
        type = "ClusterIP";
        selector.app = "mission-control";
        ports = {
          _namedlist = true;
          http = {
            port = 3000;
            targetPort = 3000;
            protocol = "TCP";
          };
        };
      };
    };

    # ── NetworkPolicy: ingress from caddy + cluster ────────────────────
    orchestration.NetworkPolicy.allow-mc-ingress = {
      metadata.labels = {
        app = "mission-control";
        policy = "allow-ingress";
      };
      spec = {
        podSelector.matchLabels.app = "mission-control";
        policyTypes = [ "Ingress" ];
        ingress = [
          {
            from = [
              { namespaceSelector.matchLabels.name = "ingress-system"; }
            ];
            ports = [
              { protocol = "TCP"; port = 3000; }
            ];
          }
          {
            from = [
              { ipBlock.cidr = "10.244.0.0/16"; }
            ];
            ports = [
              { protocol = "TCP"; port = 3000; }
            ];
          }
          {
            from = [
              { ipBlock.cidr = "10.1.1.0/24"; }
            ];
            ports = [
              { protocol = "TCP"; port = 3000; }
            ];
          }
        ];
      };
    };

    # ── NetworkPolicy: egress (DNS + internet) ─────────────────────────
    orchestration.NetworkPolicy.allow-mc-egress = {
      metadata.labels = {
        app = "mission-control";
        policy = "allow-egress";
      };
      spec = {
        podSelector.matchLabels.app = "mission-control";
        policyTypes = [ "Egress" ];
        egress = [
          {
            to = [ { ipBlock.cidr = "0.0.0.0/0"; } ];
            ports = [
              { protocol = "UDP"; port = 53; }
              { protocol = "TCP"; port = 53; }
              { protocol = "TCP"; port = 443; }
              { protocol = "TCP"; port = 80; }
            ];
          }
        ];
      };
    };

    # ── Ingress ────────────────────────────────────────────────────────
    orchestration.Ingress.mission-control = {
      metadata.annotations = {
        "caddy.ingress.kubernetes.io/disable-ssl-redirect" = "true";
      };
      spec = {
        ingressClassName = "caddy";
        rules = [
          {
            host = "mission-control.lan";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "mission-control";
                  port.number = 3000;
                };
              }
            ];
          }
          {
            host = "mc.cluster.local";
            http.paths = [
              {
                path = "/";
                pathType = "Prefix";
                backend.service = {
                  name = "mission-control";
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

{
  config,
  lib,
  ...
}: let
  # Pinned to latest published GHCR tag (sha-90a5615, Apr 14 2026)
  # Latest commit a020d1b has failing CI, no published image yet.
  # Check: https://github.com/builderz-labs/mission-control/pkgs/container/mission-control/versions
  mcImage = "ghcr.io/builderz-labs/mission-control:sha-90a5615";

  # Pod targets forge -- local-path SC works there.
  # Sentry has DiskPressure, nexus is down, zephyr is OOM-constrained.
  # NOTE: local-path PVC is node-bound. If forge goes down, data stays there.
  # TODO: when sentry disk is fixed, consider NFS with SQLite journal_mode=DELETE.
  targetNode = "forge";
in {
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

    # ── PVC (local-path on forge) ─────────────────────────────────────
    # SQLite WAL mode does NOT work on NFS (process hangs in D-state).
    # Using local-path SC which binds to the node the pod runs on.
    orchestration.PersistentVolumeClaim.mission-control-data = {
      spec = {
        accessModes = ["ReadWriteOnce"];
        storageClassName = "local-path";
        resources.requests.storage = "2Gi";
      };
    };

    # ── Secret ─────────────────────────────────────────────────────────
    # Populated by kubectl-apply-k8s-secrets from agenix:
    #   auth-pass ← /run/agenix/mission-control-auth-pass
    #   api-key   ← /run/agenix/mission-control-api-key
    orchestration.Secret.mission-control-secrets = {
      type = "Opaque";
      stringData = {
        auth-pass = "";
        api-key = "";
      };
    };
    orchestration.Secret.mission-control-oidc = {
      type = "Opaque";
      stringData = {
        client-id = "8600c54d3e2177f24f43";
        cookie-secret = "a3f1d9c7b8e04562a1b3c4d5e6f78901";
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
                  MC_ALLOWED_HOSTS.value = "mission-control.lan,mc.cluster.local,10.1.1.100,10.1.1.110,10.244.0.0/16,localhost,127.0.0.1";
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
                # TCP probes -- httpGet probes hang when SQLite is in D-state
                startupProbe = {
                  tcpSocket.port = 3000;
                  initialDelaySeconds = 10;
                  periodSeconds = 5;
                  timeoutSeconds = 3;
                  failureThreshold = 18;
                };
                livenessProbe = {
                  tcpSocket.port = 3000;
                  initialDelaySeconds = 60;
                  periodSeconds = 30;
                  timeoutSeconds = 5;
                  failureThreshold = 3;
                };
                readinessProbe = {
                  tcpSocket.port = 3000;
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
                  tmp = {
                    mountPath = "/tmp";
                  };
                };
              };

              # Sidecar removed: auth handled by Caddy forward_auth → central-auth
            };
            volumes = {
              _namedlist = true;
              data = {
                persistentVolumeClaim.claimName = "mission-control-data";
              };
              tmp = {
                emptyDir = {};
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
        type = "NodePort";
        selector.app = "mission-control";
        ports = {
          _namedlist = true;
          http = {
            port = 3000;
            targetPort = 3000;
            nodePort = 32101;
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
        policyTypes = ["Ingress"];
        ingress = [
          {
            from = [
              {namespaceSelector.matchLabels.name = "ingress-system";}
            ];
            ports = [
              {
                protocol = "TCP";
                port = 3000;
              }
            ];
          }
          {
            from = [
              {ipBlock.cidr = "10.244.0.0/16";}
            ];
            ports = [
              {
                protocol = "TCP";
                port = 3000;
              }
            ];
          }
          {
            from = [
              {ipBlock.cidr = "10.1.1.0/24";}
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

    # ── NetworkPolicy: egress (DNS + internet) ─────────────────────────
    orchestration.NetworkPolicy.allow-mc-egress = {
      metadata.labels = {
        app = "mission-control";
        policy = "allow-egress";
      };
      spec = {
        podSelector.matchLabels.app = "mission-control";
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
                port = 443;
              }
              {
                protocol = "TCP";
                port = 80;
              }
            ];
          }
        ];
      };
    };
  };
}

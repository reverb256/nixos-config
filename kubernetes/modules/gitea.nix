{
  pkgs,
  cluster,
  nexusPreferredAffinity,
  ...
}: let
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };

  namespace = "gitea";
  nodePort = 30954;
in {
  config.kubernetes.objects = {
    # ── Namespace ──────────────────────────────────────────────────
    none.Namespace.gitea = {
      metadata.labels = {
        name = namespace;
        "pod-security.kubernetes.io/enforce" = "baseline";
        "pod-security.kubernetes.io/audit" = "restricted";
        "pod-security.kubernetes.io/warn" = "restricted";
      };
    };

    gitea.NetworkPolicy.default-deny-all = {
      spec = {
        podSelector = {};
        policyTypes = ["Ingress" "Egress"];
      };
    };

    gitea.NetworkPolicy.allow-dns = {
      spec = {
        podSelector = {};
        policyTypes = ["Egress"];
        egress = [
          {
            to = [{
              namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "kube-system";
            }];
            ports = [
              {protocol = "UDP"; port = 53;}
              {protocol = "TCP"; port = 53;}
            ];
          }
        ];
      };
    };

    # ── TLS Secret (populated by cert-sync systemd service) ────────
    # Secret contains leaf.crt (tls.crt) and leaf.key (tls.key)
    # from /etc/ssl/cluster-ca/ — synced by gitea-cert-sync.service
    # on nexus. This secret is mounted as a volume in the Gitea pod.

    # ── PersistentVolume (local storage on nexus) ──────────────────
    gitea.PersistentVolume.gitea-data-nexus-pv = {
      spec = {
        capacity.storage = "5Gi";
        accessModes = ["ReadWriteOnce"];
        persistentVolumeReclaimPolicy = "Retain";
        storageClassName = "fast-local-ssd";
        local.path = "/data/gitea-data";
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

    gitea.PersistentVolumeClaim.gitea-data = {
      spec = {
        accessModes = ["ReadWriteOnce"];
        storageClassName = "fast-local-ssd";
        resources.requests.storage = "5Gi";
      };
    };

    # ── Gitea Deployment ───────────────────────────────────────────
    gitea.Deployment.gitea = {
      metadata.labels =
        managed
        // {
          app = "gitea";
        };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels.app = "gitea";
        strategy = {
          type = "Recreate";
        };
        template = {
          metadata.labels =
            managed
            // {
              app = "gitea";
            };
          spec = {
            nodeName = "nexus";
            automountServiceAccountToken = false;
            containers._namedlist = true;
            containers.gitea = {
              image = "docker.io/gitea/gitea:1.23";
              imagePullPolicy = "IfNotPresent";
              env._namedlist = true;
              env.USER.value = "git";
              # Gitea HTTPS configuration via environment variables
              GITEA__server__PROTOCOL.value = "https";
              GITEA__server__CERT_FILE.value = "/etc/gitea/tls/tls.crt";
              GITEA__server__KEY_FILE.value = "/etc/gitea/tls/tls.key";
              GITEA__server__HTTP_PORT.value = "3000";
              GITEA__server__DOMAIN.value = "gitea.lan";
              GITEA__server__ROOT_URL.value = "https://gitea.lan/";
              GITEA__database__DB_TYPE.value = "sqlite3";
              GITEA__database__PATH.value = "/data/gitea/gitea.db";
              GITEA__repository__ROOT.value = "/data/gitea/repos";
              GITEA__security__INSTALL_LOCK.value = "true";
              ports._namedlist = true;
              ports.http = {
                containerPort = 3000;
                name = "https";
                protocol = "TCP";
              };
              livenessProbe = {
                httpGet = {
                  path = "/";
                  port = 3000;
                  scheme = "HTTPS";
                };
                initialDelaySeconds = 30;
                periodSeconds = 30;
                failureThreshold = 3;
              };
              readinessProbe = {
                httpGet = {
                  path = "/";
                  port = 3000;
                  scheme = "HTTPS";
                };
                initialDelaySeconds = 10;
                periodSeconds = 10;
                failureThreshold = 3;
              };
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "256Mi";
                };
                limits = {
                  cpu = "1000m";
                  memory = "1Gi";
                };
              };
              securityContext = {
                runAsNonRoot = true;
                runAsUser = 1000;
                allowPrivilegeEscalation = false;
                capabilities.drop = ["ALL"];
              };
              volumeMounts._namedlist = true;
              volumeMounts.data = {
                mountPath = "/data";
              };
              volumeMounts.tls = {
                mountPath = "/etc/gitea/tls";
                readOnly = true;
              };
            };
            volumes._namedlist = true;
            volumes.data.persistentVolumeClaim = {
              claimName = "gitea-data";
            };
            volumes.tls.secret = {
              secretName = "gitea-tls";
            };
          };
        };
      };
    };

    # ── Gitea Service (NodePort) ───────────────────────────────────
    gitea.Service.gitea = {
      metadata.labels =
        managed
        // {
          app = "gitea";
        };
      spec = {
        type = "NodePort";
        selector.app = "gitea";
        ports._namedlist = true;
        ports.https = {
          port = 3000;
          targetPort = 3000;
          nodePort = nodePort;
          protocol = "TCP";
        };
      };
    };
  };
}

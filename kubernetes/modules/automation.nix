{
  config,
  lib,
  ...
}: let
  # ── Version pinning ──────────────────────────────────────────────────
  # n8n: 1.123.42
  n8nImage = "n8nio/n8n:1.123.42";
  postgresImage = "docker.io/library/postgres:15-alpine";

  # ── Cluster placement ────────────────────────────────────────────────
  # Default all non-infrastructure workloads to Nexus (46GB RAM).
  targetNode = "nexus";
  ns = "automation";

  # ── Labels ───────────────────────────────────────────────────────────
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
    "app.kubernetes.io/part-of" = "automation";
  };
in {
  config.kubernetes.objects = {
    none.Namespace.${ns} = {
      metadata.labels =
        managed
        // {
          name = ns;
          "pod-security.kubernetes.io/enforce" = "baseline";
          "pod-security.kubernetes.io/audit" = "restricted";
          "pod-security.kubernetes.io/warn" = "restricted";
        };
    };
  };

  config.kubernetes.objects.${ns} = {
    # ══════════════════════════════════════════════════════════════════════
    # SECRETS
    # ══════════════════════════════════════════════════════════════════════
    Secret.n8n-secrets = {
      type = "Opaque";
      stringData = {
        # Populated by sops-nix: kubectl-apply-k8s-secrets automation n8n-secrets
        # admin-password, encryption-key, postgres-password
        postgres-password = "";
      };
    };

    Secret.hermes-automation-keys = {
      type = "Opaque";
      stringData = {
        # Populated by sops-nix: kubectl-apply-k8s-secrets automation hermes-automation-keys n8n-api-key
      };
    };

    # ══════════════════════════════════════════════════════════════════════
    # POSTGRES — n8n database
    # ══════════════════════════════════════════════════════════════════════
    StatefulSet.postgres-n8n = {
      metadata.labels =
        managed
        // {
          "app.kubernetes.io/component" = "database";
          "app" = "postgres-n8n";
        };
      spec = {
        serviceName = "postgres-n8n";
        replicas = 1;
        selector.matchLabels = {"app" = "postgres-n8n";};
        template = {
          metadata.labels = {
            "app" = "postgres-n8n";
            "app.kubernetes.io/component" = "database";
          };
          spec = {
            nodeSelector."kubernetes.io/hostname" = targetNode;
            securityContext = {
              fsGroup = 999;
            };
            containers._namedlist = true;
            containers.postgres = {
              image = postgresImage;
              imagePullPolicy = "IfNotPresent";
              ports._namedlist = true;
              ports.postgres = {
                containerPort = 5432;
                protocol = "TCP";
              };
              env._namedlist = true;
              env = {
                POSTGRES_DB.value = "n8n";
                POSTGRES_USER.value = "n8n";
                POSTGRES_PASSWORD.valueFrom.secretKeyRef = {
                  name = "n8n-secrets";
                  key = "postgres-password";
                };
                PGDATA.value = "/var/lib/postgresql/data/pgdata";
              };
              resources = {
                requests = {
                  cpu = "250m";
                  memory = "256Mi";
                };
                limits = {
                  cpu = "500m";
                  memory = "512Mi";
                };
              };
              livenessProbe = {
                exec.command = ["pg_isready" "-U" "n8n" "-d" "n8n"];
                initialDelaySeconds = 20;
                periodSeconds = 10;
                timeoutSeconds = 5;
                failureThreshold = 6;
              };
              readinessProbe = {
                exec.command = ["pg_isready" "-U" "n8n" "-d" "n8n"];
                initialDelaySeconds = 5;
                periodSeconds = 5;
                timeoutSeconds = 3;
                failureThreshold = 3;
              };
              volumeMounts._namedlist = true;
              volumeMounts.data.mountPath = "/var/lib/postgresql/data";
            };
          };
        };
        volumeClaimTemplates = [
          {
            metadata.name = "data";
            spec = {
              accessModes = ["ReadWriteOnce"];
              storageClassName = "local-path";
              resources.requests.storage = "5Gi";
            };
          }
        ];
      };
    };

    Service.postgres-n8n = {
      metadata.labels = managed // {"app.kubernetes.io/component" = "database";};
      spec = {
        type = "ClusterIP";
        selector = {"app" = "postgres-n8n";};
        ports._namedlist = true;
        ports.postgres = {
          port = 5432;
          targetPort = 5432;
          protocol = "TCP";
        };
      };
    };

    # ══════════════════════════════════════════════════════════════════════
    # N8N — Workflow automation platform
    # ══════════════════════════════════════════════════════════════════════
    Deployment.n8n = {
      metadata.labels = managed // {"app" = "n8n";};
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        strategy.type = "Recreate";
        selector.matchLabels = {"app" = "n8n";};
        template = {
          metadata.labels = {"app" = "n8n";};
          spec = {
            nodeSelector."kubernetes.io/hostname" = targetNode;
            containers._namedlist = true;
            containers.n8n = {
              image = n8nImage;
              imagePullPolicy = "IfNotPresent";
              ports._namedlist = true;
              ports.http = {
                containerPort = 5678;
                protocol = "TCP";
              };
              env._namedlist = true;
              env = {
                N8N_HOST.value = "0.0.0.0";
                N8N_PORT.value = "5678";
                N8N_PROTOCOL.value = "http";
                WEBHOOK_URL.value = "http://n8n.${ns}.svc.cluster.local:5678/";
                DB_TYPE.value = "postgresdb";
                DB_POSTGRESDB_HOST.value = "postgres-n8n";
                DB_POSTGRESDB_PORT.value = "5432";
                DB_POSTGRESDB_DATABASE.value = "n8n";
                DB_POSTGRESDB_USER.value = "n8n";
                DB_POSTGRESDB_PASSWORD.valueFrom.secretKeyRef = {
                  name = "n8n-secrets";
                  key = "postgres-password";
                };
                N8N_ENCRYPTION_KEY.valueFrom.secretKeyRef = {
                  name = "n8n-secrets";
                  key = "encryption-key";
                };
                NODE_ENV.value = "production";
                N8N_DIAGNOSTICS_ENABLED.value = "false";
                N8N_PERSONALIZATION_ENABLED.value = "false";
                N8N_VERSION_NOTIFICATIONS_ENABLED.value = "false";
              };
              resources = {
                requests = {
                  cpu = "250m";
                  memory = "512Mi";
                };
                limits = {
                  cpu = "500m";
                  memory = "1Gi";
                };
              };
            };
          };
        };
      };
    };

    Service.n8n = {
      metadata.labels = managed;
      spec = {
        type = "NodePort";
        selector = {"app" = "n8n";};
        ports._namedlist = true;
        ports.http = {
          port = 5678;
          nodePort = 32127;
          targetPort = 5678;
          protocol = "TCP";
        };
      };
    };

    # ══════════════════════════════════════════════════════════════════════
    # NETWORK POLICY — Default deny + DNS egress
    # ══════════════════════════════════════════════════════════════════════
    NetworkPolicy.default-deny-all = {
      spec = {
        podSelector.matchLabels = {};
        policyTypes = ["Ingress" "Egress"];
      };
    };

    NetworkPolicy.allow-dns = {
      spec = {
        podSelector.matchLabels = {};
        egress = [
          {
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
            to = [{namespaceSelector.matchLabels."kubernetes.io/metadata.name" = "kube-system";}];
          }
        ];
      };
    };

    NetworkPolicy.allow-internal = {
      spec = {
        podSelector.matchLabels = {};
        ingress = [{from = [{namespaceSelector.matchLabels.name = ns;}];}];
        egress = [{to = [{namespaceSelector.matchLabels.name = ns;}];}];
      };
    };

    NetworkPolicy.allow-ingress = {
      spec = {
        podSelector.matchLabels = {};
        ingress = [{from = [{namespaceSelector.matchLabels.name = "ingress-system";}];}];
      };
    };
  };
}

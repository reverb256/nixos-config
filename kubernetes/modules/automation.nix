{
  config,
  lib,
  ...
}: let
  # ── Version pinning ──────────────────────────────────────────────────
  # activepieces: 0.37.2 (2026-04)
  # n8n: 1.97.1 (2026-04)
  # Both workloads currently scaled to 0 (not actively used).
  # ── Images ───────────────────────────────────────────────────────────
  # activepieces 0.37.2 → 0.82.1 (2026-04-24)
  # n8n 1.97.1 → 2.19.2 (2026-05-01), v2 has built-in TurboQuant
  # Both workloads scaled to 0. Verify env vars on scale-up.
  activepiecesImage = "activepieces/activepieces:0.82.2";
  n8nImage = "n8nio/n8n:1.123.42";
  postgresImage = "docker.io/library/postgres:15-alpine";
  redisImage = "docker.io/library/redis:7-alpine";

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
    Secret.activepieces-secrets = {
      type = "Opaque";
      stringData = {
        ap-api-key = "changeme-activepieces-api-key";
        ap-encryption-key = "changeme-activepieces-encryption-key";
        ap-jwt-secret = "changeme-activepieces-jwt-secret";
        postgres-password = "activepieces";
        redis-password = "activepieces";
      };
    };

    Secret.n8n-secrets = {
      type = "Opaque";
      stringData = {
        admin-password = "changeme-n8n-admin";
        encryption-key = "changeme-n8n-encryption-key";
        postgres-password = "n8n";
      };
    };

    # ══════════════════════════════════════════════════════════════════════
    # POSTGRES — Activepieces database
    # ══════════════════════════════════════════════════════════════════════
    PersistentVolumeClaim.postgres-activepieces = {
      spec = {
        accessModes = ["ReadWriteOnce"];
        storageClassName = "local-path";
        resources.requests.storage = "5Gi";
      };
    };

    Deployment.postgres-activepieces = {
      metadata.labels =
        managed
        // {
          "app.kubernetes.io/component" = "database";
          "app" = "postgres-activepieces";
        };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        strategy.type = "Recreate";
        selector.matchLabels = {"app" = "postgres-activepieces";};
        template = {
          metadata.labels = {
            "app" = "postgres-activepieces";
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
                POSTGRES_DB.value = "activepieces";
                POSTGRES_USER.value = "activepieces";
                POSTGRES_PASSWORD.valueFrom.secretKeyRef = {
                  name = "activepieces-secrets";
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
                exec.command = ["pg_isready" "-U" "activepieces" "-d" "activepieces"];
                initialDelaySeconds = 20;
                periodSeconds = 10;
                timeoutSeconds = 5;
                failureThreshold = 6;
              };
              readinessProbe = {
                exec.command = ["pg_isready" "-U" "activepieces" "-d" "activepieces"];
                initialDelaySeconds = 5;
                periodSeconds = 5;
                timeoutSeconds = 3;
                failureThreshold = 3;
              };
              volumeMounts._namedlist = true;
              volumeMounts.data.mountPath = "/var/lib/postgresql/data";
            };
            volumes._namedlist = true;
            volumes.data.persistentVolumeClaim.claimName = "postgres-activepieces";
          };
        };
      };
    };

    Service.postgres-activepieces = {
      metadata.labels = managed // {"app.kubernetes.io/component" = "database";};
      spec = {
        type = "ClusterIP";
        selector = {"app" = "postgres-activepieces";};
        ports._namedlist = true;
        ports.postgres = {
          port = 5432;
          targetPort = 5432;
          protocol = "TCP";
        };
      };
    };

    # ══════════════════════════════════════════════════════════════════════
    # POSTGRES — n8n database
    # ══════════════════════════════════════════════════════════════════════
    PersistentVolumeClaim.postgres-n8n = {
      spec = {
        accessModes = ["ReadWriteOnce"];
        storageClassName = "local-path";
        resources.requests.storage = "5Gi";
      };
    };

    Deployment.postgres-n8n = {
      metadata.labels =
        managed
        // {
          "app.kubernetes.io/component" = "database";
          "app" = "postgres-n8n";
        };
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        strategy.type = "Recreate";
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
            volumes._namedlist = true;
            volumes.data.persistentVolumeClaim.claimName = "postgres-n8n";
          };
        };
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
    # REDIS — Activepieces cache
    # ══════════════════════════════════════════════════════════════════════
    Deployment.redis-activepieces = {
      metadata.labels = managed // {"app" = "redis-activepieces";};
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        strategy.type = "Recreate";
        selector.matchLabels = {"app" = "redis-activepieces";};
        template = {
          metadata.labels = {"app" = "redis-activepieces";};
          spec = {
            nodeSelector."kubernetes.io/hostname" = targetNode;
            containers._namedlist = true;
            containers.redis = {
              image = redisImage;
              imagePullPolicy = "IfNotPresent";
              ports._namedlist = true;
              ports.redis = {
                containerPort = 6379;
                protocol = "TCP";
              };
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "64Mi";
                };
                limits = {
                  cpu = "200m";
                  memory = "128Mi";
                };
              };
              livenessProbe = {
                exec.command = ["redis-cli" "ping"];
                initialDelaySeconds = 5;
                periodSeconds = 10;
              };
              readinessProbe = {
                exec.command = ["redis-cli" "ping"];
                initialDelaySeconds = 3;
                periodSeconds = 5;
              };
            };
          };
        };
      };
    };

    Service.redis-activepieces = {
      metadata.labels = managed;
      spec = {
        type = "ClusterIP";
        selector = {"app" = "redis-activepieces";};
        ports._namedlist = true;
        ports.redis = {
          port = 6379;
          targetPort = 6379;
          protocol = "TCP";
        };
      };
    };

    # ══════════════════════════════════════════════════════════════════════
    # ACTIVEPIECES — Workflow automation platform
    # ══════════════════════════════════════════════════════════════════════
    Deployment.activepieces = {
      metadata.labels = managed // {"app" = "activepieces";};
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        strategy.type = "Recreate";
        selector.matchLabels = {"app" = "activepieces";};
        template = {
          metadata.labels = {"app" = "activepieces";};
          spec = {
            nodeSelector."kubernetes.io/hostname" = targetNode;
            containers._namedlist = true;
            containers.activepieces = {
              image = activepiecesImage;
              imagePullPolicy = "IfNotPresent";
              ports._namedlist = true;
              ports.http = {
                containerPort = 80;
                protocol = "TCP";
              };
              env._namedlist = true;
              env = {
                AP_API_KEY.valueFrom.secretKeyRef = {
                  name = "activepieces-secrets";
                  key = "ap-api-key";
                };
                AP_ENCRYPTION_KEY.valueFrom.secretKeyRef = {
                  name = "activepieces-secrets";
                  key = "ap-encryption-key";
                };
                AP_JWT_SECRET.valueFrom.secretKeyRef = {
                  name = "activepieces-secrets";
                  key = "ap-jwt-secret";
                };
                AP_ENGINE_EXECUTABLE_PATH.value = "dist/packages/engine/main.js";
                AP_EXECUTION_MODE.value = "UNSANDBOXED";
                AP_NODE_EXECUTION_TIMEOUT.value = "300";
                AP_TELEMETRY_ENABLED.value = "false";
                AP_FRONTEND_URL.value = "http://activepieces.${ns}.svc.cluster.local:80";
                AP_WEBHOOK_TIMEOUT_SECONDS.value = "30";
                DB_TYPE.value = "POSTGRES";
                AP_POSTGRES_DATABASE.value = "activepieces";
                AP_POSTGRES_HOST.value = "postgres-activepieces";
                AP_POSTGRES_PORT.value = "5432";
                AP_POSTGRES_USERNAME.value = "activepieces";
                AP_POSTGRES_PASSWORD.valueFrom.secretKeyRef = {
                  name = "activepieces-secrets";
                  key = "postgres-password";
                };
                AP_REDIS_HOST.value = "redis-activepieces";
                AP_REDIS_PORT.value = "6379";
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

    Service.activepieces = {
      metadata.labels = managed;
      spec = {
        type = "ClusterIP";
        selector = {"app" = "activepieces";};
        ports._namedlist = true;
        ports.http = {
          port = 80;
          targetPort = 80;
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
        type = "ClusterIP";
        selector = {"app" = "n8n";};
        ports._namedlist = true;
        ports.http = {
          port = 5678;
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
            to = [{namespaceSelector.matchLabels.name = "kube-system";}];
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

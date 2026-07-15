{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
  };

  cfg = config.services.maplespike;

  # Get short commit SHA for image pinning
  imageTag = "2026-05-16";

  # Common deployment builder
  mkDeployment = {
    name,
    namespace,
    cmd,
    port,
    replicaCount,
    image,
    resources,
    envExtra ? [],
    nodeName ? null,
    runAsUser ? 1001,
    runAsGroup ? 1001,
  }: let
    labels = {
      app = "maplespike-${name}";
      component = name;
      tier = "backend";
    };
  in {
    apiVersion = "apps/v1";
    kind = "Deployment";
    metadata = {
      inherit name namespace labels;
    };
    spec = {
      replicas = replicaCount;
      revisionHistoryLimit = 2;
      selector = {
        matchLabels = {
          inherit (labels) app;
        };
      };
      strategy = {
        rollingUpdate = {
          maxSurge = 1;
          maxUnavailable = 0;
        };
      };
      template = {
        metadata.labels = labels;
        spec =
          lib.optionalAttrs (nodeName != null) { inherit nodeName; }
          // {
          securityContext = {
            inherit runAsUser;
            inherit runAsGroup;
            fsGroup = runAsGroup;
          };
          terminationGracePeriodSeconds = 30;
          imagePullSecrets = [{name = "ghcr-pull";}];
          affinity = {
            podAntiAffinity = {
              preferredDuringSchedulingIgnoredDuringExecution = [
                {
                  weight = 100;
                  podAffinityTerm = {
                    labelSelector.matchLabels = {
                      inherit (labels) app;
                    };
                    topologyKey = "kubernetes.io/hostname";
                  };
                }
              ];
            };
            nodeAffinity = {
              preferredDuringSchedulingIgnoredDuringExecution = [
                {
                  weight = 80;
                  preference.matchExpressions = [
                    {
                      key = "kubernetes.io/hostname";
                      operator = "In";
                      values = ["nexus" "sentry"];
                    }
                  ];
                }
                {
                  weight = 50;
                  preference.matchExpressions = [
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
          topologySpreadConstraints = [
            {
              maxSkew = 1;
              topologyKey = "kubernetes.io/hostname";
              whenUnsatisfiable = "ScheduleAnyway";
              labelSelector.matchLabels = {
                inherit (labels) app;
              };
            }
          ];
          containers = [
            {
              inherit name image;
              imagePullPolicy = "IfNotPresent";
              ports = lib.mkIf (port > 0) [
                {
                  containerPort = port;
                }
              ];
              env =
                [
                  {
                    name = "PORT";
                    value = toString port;
                  }
                  {
                    name = "NODE_ENV";
                    value = "production";
                  }
                ]
                ++ envExtra;
              inherit resources;
              securityContext = {
                allowPrivilegeEscalation = false;
                capabilities = {
                  drop = ["ALL"];
                };
                runAsNonRoot = true;
                inherit runAsUser;
                seccompProfile = {
                  type = "RuntimeDefault";
                };
              };
            }
          ];
        };
      };
    };
  };
in {
  options.services.maplespike = {
    enable = mkEnableOption "MapleSpike deployments";

    images = {
      api = mkOption {
        type = types.str;
        default = "ghcr.io/reverb256/maplespike-api:${imageTag}";
        description = "Maplespike API container image (pinned version)";
      };
      mcp = mkOption {
        type = types.str;
        default = "ghcr.io/reverb256/maplespike-mcp:${imageTag}";
        description = "Maplespike MCP server container image (pinned version)";
      };
      portal = mkOption {
        type = types.str;
        default = "ghcr.io/reverb256/maplespike-portal:${imageTag}";
        description = "Maplespike portal container image (pinned version)";
      };
    };

    stagingImages = {
      api = mkOption {
        type = types.str;
        default = "ghcr.io/reverb256/maplespike-api:${imageTag}-staging";
        description = "Maplespike API staging container image (pinned version)";
      };
      mcp = mkOption {
        type = types.str;
        default = "ghcr.io/reverb256/maplespike-mcp:${imageTag}-staging";
        description = "Maplespike MCP staging container image (pinned version)";
      };
      portal = mkOption {
        type = types.str;
        default = "ghcr.io/reverb256/maplespike-portal:${imageTag}-staging";
        description = "Maplespike portal staging container image (pinned version)";
      };
    };

    replicas = {
      api = mkOption {
        type = types.int;
        default = 2;
      };
      mcp = mkOption {
        type = types.int;
        default = 2;
      };
      portal = mkOption {
        type = types.int;
        default = 2;
      };
      stagingApi = mkOption {
        type = types.int;
        default = 1;
      };
      stagingMcp = mkOption {
        type = types.int;
        default = 1;
      };
    };
  };

  config.kubernetes.objects = mkIf cfg.enable {
    # ── Namespaces ──────────────────────────────────────────
    none.Namespace.maplespike-prod = {
      metadata.labels =
        managed
        // {
          name = "maplespike-prod";
          "pod-security.kubernetes.io/enforce" = "baseline";
          "pod-security.kubernetes.io/audit" = "restricted";
          "pod-security.kubernetes.io/warn" = "restricted";
        };
    };

    none.Namespace.maplespike-staging = {
      metadata.labels =
        managed
        // {
          name = "maplespike-staging";
          "pod-security.kubernetes.io/enforce" = "baseline";
          "pod-security.kubernetes.io/audit" = "restricted";
          "pod-security.kubernetes.io/warn" = "restricted";
        };
    };

    # ── Prod Deployments (maplespike-prod namespace) ──────────
    "maplespike-prod".Deployment.maplespike-api = mkDeployment {
      name = "maplespike-api";
      namespace = "maplespike-prod";
      cmd = "node packages/api-server/dist/dev-server.js";
      port = 8082;
      replicaCount = cfg.replicas.api;
      image = cfg.images.api;
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
    };

    "maplespike-prod".Deployment.maplespike-mcp =
      mkDeployment {
        name = "maplespike-mcp";
        namespace = "maplespike-prod";
        cmd = "node packages/mcp-server/dist/index.js";
        port = 3001;
        replicaCount = cfg.replicas.mcp;
        image = cfg.images.mcp;
        resources = {
          requests = {
            cpu = "100m";
            memory = "128Mi";
          };
          limits = {
            cpu = "300m";
            memory = "256Mi";
          };
        };
      }
      // {spec.template.spec.serviceAccountName = "maplespike-mcp-maplespike-prod";};

    "maplespike-prod".Deployment.maplespike-portal = mkDeployment {
      name = "maplespike-portal";
      namespace = "maplespike-prod";
      cmd = "nginx -g 'daemon off;'";
      port = 8080;
      replicaCount = cfg.replicas.portal;
      image = cfg.images.portal;
      resources = {
        requests = {
          cpu = "50m";
          memory = "64Mi";
        };
        limits = {
          cpu = "100m";
          memory = "128Mi";
        };
      };
    };

    # ── Staging Deployments (maplespike-staging namespace) ─────
    "maplespike-staging".Deployment.maplespike-api = mkDeployment {
      name = "maplespike-api";
      namespace = "maplespike-staging";
      cmd = "node packages/api-server/dist/dev-server.js";
      port = 8082;
      replicaCount = cfg.replicas.stagingApi;
      image = cfg.stagingImages.api;
      resources = {
        requests = {
          cpu = "100m";
          memory = "128Mi";
        };
        limits = {
          cpu = "300m";
          memory = "256Mi";
        };
      };
    };

    "maplespike-staging".Deployment.maplespike-mcp =
      mkDeployment {
        name = "maplespike-mcp";
        namespace = "maplespike-staging";
        cmd = "node packages/mcp-server/dist/index.js";
        port = 3001;
        replicaCount = cfg.replicas.stagingMcp;
        image = cfg.stagingImages.mcp;
        resources = {
          requests = {
            cpu = "100m";
            memory = "128Mi";
          };
          limits = {
            cpu = "300m";
            memory = "256Mi";
          };
        };
      }
      // {spec.template.spec.serviceAccountName = "maplespike-mcp-maplespike-staging";};

    "maplespike-staging".Deployment.maplespike-portal = mkDeployment {
      name = "maplespike-portal";
      namespace = "maplespike-staging";
      cmd = "nginx -g 'daemon off;'";
      port = 8080;
      replicaCount = 1;
      image = cfg.stagingImages.portal;
      resources = {
        requests = {
          cpu = "50m";
          memory = "64Mi";
        };
        limits = {
          cpu = "100m";
          memory = "128Mi";
        };
      };
    };

    # ── MCP ServiceAccounts & RBAC (per namespace) ───────────
    "maplespike-prod".ServiceAccount."maplespike-mcp-maplespike-prod" = {
      metadata.labels = managed;
      metadata.annotations = {
        "kubernetes.io/enforce-no-automount-token" = "false";
      };
    };

    "maplespike-staging".ServiceAccount."maplespike-mcp-maplespike-staging" = {
      metadata.labels = managed;
      metadata.annotations = {
        "kubernetes.io/enforce-no-automount-token" = "false";
      };
    };

    none.ClusterRole.maplespike-mcp-audit = {
      metadata.labels = managed;
      rules = [
        {
          apiGroups = ["rbac.authorization.k8s.io"];
          resources = ["clusterroles" "clusterrolebindings" "roles" "rolebindings"];
          verbs = ["get" "list" "watch"];
        }
        {
          apiGroups = [""];
          resources = ["namespaces" "serviceaccounts"];
          verbs = ["get" "list"];
        }
        {
          apiGroups = ["authorization.k8s.io"];
          resources = ["selfsubjectaccessreviews" "selfsubjectrulesreviews"];
          verbs = ["create"];
        }
      ];
    };

    none.ClusterRoleBinding."maplespike-mcp-audit-maplespike-prod" = {
      metadata.labels = managed;
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "maplespike-mcp-audit";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = "maplespike-mcp-maplespike-prod";
          namespace = "maplespike-prod";
        }
      ];
    };

    none.ClusterRoleBinding."maplespike-mcp-audit-maplespike-staging" = {
      metadata.labels = managed;
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "maplespike-mcp-audit";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = "maplespike-mcp-maplespike-staging";
          namespace = "maplespike-staging";
        }
      ];
    };

    # ── Services (per namespace) ──────────────────────────────
    "maplespike-prod".Service.maplespike-api = {
      metadata.labels = managed // {app = "maplespike-api";};
      spec = {
        selector = {app = "maplespike-api";};
        ports = [
          {
            port = 8080;
            targetPort = 8082;
            protocol = "TCP";
            name = "http";
          }
          {
            port = 8082;
            targetPort = 8082;
            protocol = "TCP";
            name = "api";
          }
        ];
        type = "ClusterIP";
      };
    };

    "maplespike-prod".Service.maplespike-mcp = {
      metadata.labels = managed // {app = "maplespike-mcp";};
      spec = {
        selector = {app = "maplespike-mcp";};
        ports = [
          {
            port = 3001;
            targetPort = 3001;
            protocol = "TCP";
            name = "mcp";
          }
        ];
        type = "ClusterIP";
      };
    };

    "maplespike-prod".Service.maplespike-portal = {
      metadata.labels = managed // {app = "maplespike-portal";};
      spec = {
        selector = {app = "maplespike-portal";};
        ports = [
          {
            port = 80;
            targetPort = 80;
            protocol = "TCP";
            name = "http";
          }
        ];
        type = "ClusterIP";
      };
    };

    "maplespike-staging".Service.maplespike-api = {
      metadata.labels = managed // {app = "maplespike-api";};
      spec = {
        selector = {app = "maplespike-api";};
        ports = [
          {
            port = 8080;
            targetPort = 8082;
            protocol = "TCP";
            name = "http";
          }
          {
            port = 8082;
            targetPort = 8082;
            protocol = "TCP";
            name = "api";
          }
        ];
        type = "ClusterIP";
      };
    };

    "maplespike-staging".Service.maplespike-mcp = {
      metadata.labels = managed // {app = "maplespike-mcp";};
      spec = {
        selector = {app = "maplespike-mcp";};
        ports = [
          {
            port = 3001;
            targetPort = 3001;
            protocol = "TCP";
            name = "mcp";
          }
        ];
        type = "ClusterIP";
      };
    };

    "maplespike-staging".Service.maplespike-portal = {
      metadata.labels = managed // {app = "maplespike-portal";};
      spec = {
        selector = {app = "maplespike-portal";};
        ports = [
          {
            port = 80;
            targetPort = 8080;
            protocol = "TCP";
            name = "http";
          }
        ];
        type = "ClusterIP";
      };
    };
  };
}

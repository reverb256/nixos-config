{
  cluster,
  config,
  lib,
  ...
}: let
  # ── Version pinning ──────────────────────────────────────────────────
  # kagent v0.9.0 (2026-04-22) — latest stable release
  # Registry: cr.kagent.dev (kagent's official container registry)
  # Check: https://github.com/kagent-dev/kagent/releases
  version = "0.9.4";
  registry = "cr.kagent.dev";

  # ── Image references ─────────────────────────────────────────────────
  controllerImage = "${registry}/kagent-dev/kagent/controller:${version}";
  uiImage = "${registry}/kagent-dev/kagent/ui:${version}";
  postgresImage = "docker.io/library/postgres:18.3-alpine";

  # ── Cluster placement ────────────────────────────────────────────────
  # All kagent components on Nexus (46GB RAM, control plane)
  targetNode = "nexus";
  ns = "kagent";

  # ── Labels ───────────────────────────────────────────────────────────
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
    "app.kubernetes.io/part-of" = "kagent";
  };

  # ── nginx.conf for UI ────────────────────────────────────────────────
  # Proxies Next.js (port 8001) and controller API (port 8083) through
  # nginx (port 8080). Based on helm/kagent/files/nginx.conf.
  nginxConf = ''
    pid /tmp/nginx.pid;
    error_log /dev/stderr;
    events { worker_connections 1024; }
    http {
        client_body_temp_path /tmp/nginx/client_temp;
        proxy_temp_path /tmp/nginx/proxy_temp;
        fastcgi_temp_path /tmp/nginx/fastcgi_temp;
        uwsgi_temp_path /tmp/nginx/uwsgi_temp;
        scgi_temp_path /tmp/nginx/scgi_temp;
        access_log /dev/stdout;

        upstream kagent_ui { server 127.0.0.1:8001; }
        upstream kagent_ws_backend { server 127.0.0.1:8081; }
        upstream kagent_backend { server kagent-controller.${ns}.svc.cluster.local:8083; }

        map $http_upgrade $connection_upgrade {
            default upgrade;
            ''' close;
        }

        server {
            listen 8080;
            server_name localhost;

            location /a2a/ {
                proxy_pass http://kagent_ui/a2a/;
                proxy_http_version 1.1;
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection $connection_upgrade;
                proxy_set_header Host $host;
                proxy_read_timeout 600s;
                proxy_buffering off;
            }

            location / {
                proxy_pass http://kagent_ui;
                proxy_http_version 1.1;
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection $connection_upgrade;
                proxy_set_header Host $host;
            }

            location /health {
                return 200 'OK';
                add_header Content-Type text/plain;
            }

            location /api/ {
                proxy_pass http://kagent_backend/api/;
                proxy_http_version 1.1;
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
            }

            location /api/ws/ {
                proxy_pass http://kagent_ws_backend/api/ws/;
                proxy_http_version 1.1;
                proxy_set_header Upgrade $http_upgrade;
                proxy_set_header Connection $connection_upgrade;
                proxy_set_header Host $host;
                proxy_read_timeout 300s;
                proxy_buffering off;
            }
        }
    }
  '';

  # ── supervisord.conf for UI ──────────────────────────────────────────
  supervisordConf = ''
    [supervisord]
    nodaemon=true
    logfile=/dev/stdout
    logfile_maxbytes=0
    loglevel=debug

    [program:nginx]
    command=/usr/sbin/nginx -g "daemon off;"
    autostart=true
    autorestart=true
    priority=20

    [program:nextjs]
    command=node /app/ui/server.js
    directory=/app/ui
    environment=PORT="8001",HOSTNAME="0.0.0.0",NODE_ENV="production"
    autostart=true
    autorestart=true
    priority=10
  '';

  # ── RBAC rules (shared between getter and writer) ────────────────────
  crdResources = [
    "agents"
    "sandboxagents"
    "modelconfigs"
    "modelproviderconfigs"
    "toolservers"
    "memories"
    "remotemcpservers"
    "mcpservers"
  ];
  crdStatuses = map (r: r + "/status") crdResources;
  crdFinalizers = map (r: r + "/finalizers") crdResources;
in {
  config.kubernetes.objects = {
    # ══════════════════════════════════════════════════════════════════════
    # NAMESPACE (cluster-scoped, use 'none' prefix)
    # ══════════════════════════════════════════════════════════════════════
    none.Namespace.${ns} = {
      metadata.labels =
        {
          name = ns;
          "pod-security.kubernetes.io/enforce" = "baseline";
          "pod-security.kubernetes.io/audit" = "restricted";
          "pod-security.kubernetes.io/warn" = "restricted";
        }
        // managed;
    };

    # ══════════════════════════════════════════════════════════════════════
    # RBAC — Controller needs cluster-wide access to manage CRDs and pods
    # ══════════════════════════════════════════════════════════════════════
    none.ClusterRole.kagent-getter = {
      metadata.labels = managed;
      rules = [
        {
          apiGroups = ["kagent.dev"];
          resources = crdResources;
          verbs = ["get" "list" "watch"];
        }
        {
          apiGroups = ["kagent.dev"];
          resources = crdStatuses;
          verbs = ["get" "patch" "update"];
        }
        {
          apiGroups = ["kagent.dev"];
          resources = crdFinalizers;
          verbs = ["update"];
        }
        {
          apiGroups = [""];
          resources = ["*"];
          verbs = ["get" "list" "watch"];
        }
        {
          apiGroups = ["apps"];
          resources = ["*"];
          verbs = ["get" "list" "watch"];
        }
        {
          apiGroups = ["batch"];
          resources = ["*"];
          verbs = ["get" "list" "watch"];
        }
        {
          apiGroups = ["rbac.authorization.k8s.io"];
          resources = ["*"];
          verbs = ["get" "list" "watch"];
        }
      ];
    };

    none.ClusterRoleBinding.kagent-getter = {
      metadata.labels = managed;
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "kagent-getter";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = "kagent-controller";
          namespace = ns;
        }
      ];
    };

    none.ClusterRole.kagent-writer = {
      metadata.labels = managed;
      rules = [
        {
          apiGroups = ["kagent.dev"];
          resources = crdResources;
          verbs = ["create" "update" "patch" "delete"];
        }
        {
          apiGroups = ["kagent.dev"];
          resources = crdFinalizers;
          verbs = ["update"];
        }
        {
          apiGroups = [""];
          resources = ["*"];
          verbs = ["create" "update" "patch" "delete"];
        }
        {
          apiGroups = ["apps"];
          resources = ["*"];
          verbs = ["create" "update" "patch" "delete"];
        }
        {
          apiGroups = ["batch"];
          resources = ["*"];
          verbs = ["create" "update" "patch" "delete"];
        }
      ];
    };

    none.ClusterRoleBinding.kagent-writer = {
      metadata.labels = managed;
      roleRef = {
        apiGroup = "rbac.authorization.k8s.io";
        kind = "ClusterRole";
        name = "kagent-writer";
      };
      subjects = [
        {
          kind = "ServiceAccount";
          name = "kagent-controller";
          namespace = ns;
        }
      ];
    };

    # ══════════════════════════════════════════════════════════════════════
    # SERVICE ACCOUNTS
    # ══════════════════════════════════════════════════════════════════════
    kagent.ServiceAccount.kagent-controller = {};
    kagent.ServiceAccount.kagent-ui.automountServiceAccountToken = false;
    kagent.ServiceAccount.kagent-postgresql = {};

    # ══════════════════════════════════════════════════════════════════════
    # POSTGRESQL — Bundled database for controller state
    # ══════════════════════════════════════════════════════════════════════
    kagent.Secret.kagent-postgresql = {
      type = "Opaque";
      # TODO: Fill from agenix key `kagent-postgres` (see modules/system/agenix-secrets-registry.nix)
      stringData.POSTGRES_PASSWORD = "";
    };

    kagent.PersistentVolumeClaim.kagent-postgresql = {
      metadata.labels = managed // {"app.kubernetes.io/component" = "database";};
      spec = {
        accessModes = ["ReadWriteOnce"];
        storageClassName = "local-path";
        resources.requests.storage = "2Gi";
      };
    };

    kagent.Deployment.kagent-postgresql = {
      metadata.labels = managed // {"app.kubernetes.io/component" = "database";};
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        strategy.type = "Recreate";
        selector.matchLabels = {"app.kubernetes.io/component" = "database";};
        template = {
          metadata.labels = managed // {"app.kubernetes.io/component" = "database";};
          spec = {
            nodeSelector."kubernetes.io/hostname" = targetNode;
            serviceAccountName = "kagent-postgresql";
            imagePullSecrets = [{name = "ghcr-pull";}];
            securityContext = {
              fsGroup = 999;
              runAsUser = 999;
              runAsGroup = 999;
              runAsNonRoot = true;
              seccompProfile.type = "RuntimeDefault";
            };
            containers._namedlist = true;
            containers.postgresql = {
              image = postgresImage;
              imagePullPolicy = "IfNotPresent";
              ports._namedlist = true;
              ports.postgresql = {
                containerPort = 5432;
                protocol = "TCP";
              };
              env._namedlist = true;
              env = {
                POSTGRES_DB.value = "kagent";
                POSTGRES_USER.value = "kagent";
                POSTGRES_PASSWORD.valueFrom.secretKeyRef = {
                  name = "kagent-postgresql";
                  key = "POSTGRES_PASSWORD";
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
                exec.command = ["pg_isready" "-U" "kagent" "-d" "kagent"];
                initialDelaySeconds = 20;
                periodSeconds = 10;
                timeoutSeconds = 5;
                failureThreshold = 6;
              };
              readinessProbe = {
                exec.command = ["pg_isready" "-U" "kagent" "-d" "kagent"];
                initialDelaySeconds = 5;
                periodSeconds = 5;
                timeoutSeconds = 3;
                failureThreshold = 3;
              };
              securityContext = {
                allowPrivilegeEscalation = false;
                capabilities.drop = ["ALL"];
                seccompProfile.type = "RuntimeDefault";
              };
              volumeMounts._namedlist = true;
              volumeMounts.data.mountPath = "/var/lib/postgresql/data";
            };
            volumes._namedlist = true;
            volumes.data.persistentVolumeClaim.claimName = "kagent-postgresql";
          };
        };
      };
    };

    kagent.Service.kagent-postgresql = {
      metadata.labels = managed // {"app.kubernetes.io/component" = "database";};
      spec = {
        type = "ClusterIP";
        selector = {"app.kubernetes.io/component" = "database";};
        ports._namedlist = true;
        ports.postgresql = {
          port = 5432;
          targetPort = 5432;
          protocol = "TCP";
        };
      };
    };

    # ══════════════════════════════════════════════════════════════════════
    # CONTROLLER — Watches CRDs, runs agents, manages pods
    # ══════════════════════════════════════════════════════════════════════
    kagent.ConfigMap.kagent-controller = {
      metadata.labels = managed;
      data = {
        A2A_BASE_URL = "http://kagent-controller.${ns}.svc.cluster.local:8083";
        DEFAULT_MODEL_CONFIG_NAME = "gateway-local";
        KAGENT_CONTROLLER_NAME = "kagent-controller";
        IMAGE_PULL_POLICY = "IfNotPresent";
        IMAGE_REGISTRY = registry;
        IMAGE_REPOSITORY = "kagent-dev/kagent/app";
        IMAGE_TAG = version;
        SKILLS_INIT_IMAGE_REGISTRY = registry;
        SKILLS_INIT_IMAGE_REPOSITORY = "kagent-dev/kagent/skills-init";
        SKILLS_INIT_IMAGE_TAG = version;
        LEADER_ELECT = "false";
        OTEL_TRACING_ENABLED = "false";
        OTEL_LOGGING_ENABLED = "false";
        DATABASE_VECTOR_ENABLED = "false";
        STREAMING_INITIAL_BUF_SIZE = "4096";
        STREAMING_MAX_BUF_SIZE = "1048576";
        STREAMING_TIMEOUT = "600s";
        WATCH_NAMESPACES = "";
        ZAP_LOG_LEVEL = "info";
        DEFAULT_AGENT_BIND_HOST = "0.0.0.0";
      };
    };

    kagent.Deployment.kagent-controller = {
      metadata.labels = managed // {"app.kubernetes.io/component" = "controller";};
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels = {"app.kubernetes.io/component" = "controller";};
        template = {
          metadata.labels = managed // {"app.kubernetes.io/component" = "controller";};
          spec = {
            nodeSelector."kubernetes.io/hostname" = targetNode;
            serviceAccountName = "kagent-controller";
            imagePullSecrets = [{name = "ghcr-pull";}];
            securityContext = {
              runAsNonRoot = true;
              seccompProfile.type = "RuntimeDefault";
            };
            containers._namedlist = true;
            containers.controller = {
              image = controllerImage;
              imagePullPolicy = "IfNotPresent";
              ports._namedlist = true;
              ports.http = {
                containerPort = 8083;
                protocol = "TCP";
              };
              env._namedlist = true;
              env = {
                KAGENT_NAMESPACE.valueFrom.fieldRef.fieldPath = "metadata.namespace";
                K8S_POD_NAME.valueFrom.fieldRef.fieldPath = "metadata.name";
                K8S_NODE_NAME.valueFrom.fieldRef.fieldPath = "spec.nodeName";
                AUTH_MODE.value = "trusted-proxy";
                POSTGRES_PASSWORD.valueFrom.secretKeyRef = {
                  name = "kagent-postgresql";
                  key = "POSTGRES_PASSWORD";
                };
                POSTGRES_DATABASE_URL.value = "postgres://kagent:kagent@kagent-postgresql.${ns}.svc.cluster.local:5432/kagent?sslmode=disable";
              };
              envFrom = [{configMapRef.name = "kagent-controller";}];
              resources = {
                requests = {
                  cpu = "200m";
                  memory = "256Mi";
                };
                limits = {
                  cpu = "2";
                  memory = "1Gi";
                };
              };
              securityContext = {
                readOnlyRootFilesystem = true;
                allowPrivilegeEscalation = false;
                capabilities.drop = ["ALL"];
                seccompProfile.type = "RuntimeDefault";
              };
              startupProbe = {
                httpGet = {
                  path = "/health";
                  port = 8083;
                };
                periodSeconds = 15;
                initialDelaySeconds = 15;
                failureThreshold = 10;
              };
              readinessProbe = {
                httpGet = {
                  path = "/health";
                  port = 8083;
                };
                periodSeconds = 30;
              };
              volumeMounts._namedlist = true;
              volumeMounts.tmp.mountPath = "/tmp";
            };
            volumes._namedlist = true;
            volumes.tmp.emptyDir = {};
          };
        };
      };
    };

    kagent.Service.kagent-controller = {
      metadata.labels = managed // {"app.kubernetes.io/component" = "controller";};
      spec = {
        type = "NodePort";
        selector = {"app.kubernetes.io/component" = "controller";};
        ports._namedlist = true;
        ports.controller = {
          port = 8083;
          targetPort = 8083;
          nodePort = 30794;
          protocol = "TCP";
        };
      };
    };

    # ══════════════════════════════════════════════════════════════════════
    # UI — Next.js + nginx dashboard
    # ══════════════════════════════════════════════════════════════════════
    kagent.ConfigMap.kagent-ui-config = {
      metadata.labels = managed;
      data = {
        "nginx.conf" = nginxConf;
        "supervisord.conf" = supervisordConf;
      };
    };

    kagent.Deployment.kagent-ui = {
      metadata.labels = managed // {"app.kubernetes.io/component" = "ui";};
      spec = {
        replicas = 1;
        revisionHistoryLimit = 2;
        selector.matchLabels = {"app.kubernetes.io/component" = "ui";};
        template = {
          metadata.labels = managed // {"app.kubernetes.io/component" = "ui";};
          spec = {
            nodeSelector."kubernetes.io/hostname" = targetNode;
            serviceAccountName = "kagent-ui";
            imagePullSecrets = [{name = "ghcr-pull";}];
            hostAliases = [
              {
                ip = cluster.kubernetes.vip;
                hostnames = ["auth.lan" "kagent.lan"];
              }
            ];
            securityContext = {
              runAsNonRoot = true;
              seccompProfile.type = "RuntimeDefault";
            };
            containers._namedlist = true;
            containers.ui = {
              image = uiImage;
              imagePullPolicy = "IfNotPresent";
              ports._namedlist = true;
              ports.http = {
                containerPort = 8080;
                protocol = "TCP";
              };
              env._namedlist = true;
              env = {
                NEXT_PUBLIC_BACKEND_URL.value = "http://kagent-controller.${ns}.svc.cluster.local:8083/api";
              };
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "256Mi";
                };
                limits = {
                  cpu = "1";
                  memory = "1Gi";
                };
              };
              securityContext = {
                readOnlyRootFilesystem = true;
                allowPrivilegeEscalation = false;
                capabilities.drop = ["ALL"];
                seccompProfile.type = "RuntimeDefault";
              };
              startupProbe = {
                httpGet = {
                  path = "/health";
                  port = 8080;
                };
                periodSeconds = 2;
                initialDelaySeconds = 5;
                failureThreshold = 30;
              };
              readinessProbe = {
                httpGet = {
                  path = "/health";
                  port = 8080;
                };
                periodSeconds = 30;
              };
              volumeMounts._namedlist = true;
              volumeMounts = {
                nextjs-cache.mountPath = "/app/ui/.next/cache";
                tmp.mountPath = "/tmp";
                nginx-conf = {
                  mountPath = "/etc/nginx/nginx.conf";
                  subPath = "nginx.conf";
                  readOnly = true;
                };
                supervisord-conf = {
                  mountPath = "/etc/supervisor/conf.d/supervisord.conf";
                  subPath = "supervisord.conf";
                  readOnly = true;
                };
              };
            };
            # Sidecar removed: auth handled by Caddy forward_auth → central-auth
            volumes._namedlist = true;
            volumes = {
              nextjs-cache.emptyDir.sizeLimit = "100Mi";
              tmp.emptyDir.sizeLimit = "50Mi";
              nginx-conf.configMap = {
                name = "kagent-ui-config";
                items = [
                  {
                    key = "nginx.conf";
                    path = "nginx.conf";
                  }
                ];
              };
              supervisord-conf.configMap = {
                name = "kagent-ui-config";
                items = [
                  {
                    key = "supervisord.conf";
                    path = "supervisord.conf";
                  }
                ];
              };
            };
          };
        };
      };
    };

    kagent.Service.kagent-ui = {
      metadata.labels = managed // {"app.kubernetes.io/component" = "ui";};
      spec = {
        type = "NodePort";
        selector = {"app.kubernetes.io/component" = "ui";};
        ports._namedlist = true;
        ports.http = {
          port = 8080;
          targetPort = 8080;
          nodePort = 32103;
          protocol = "TCP";
        };
      };
    };

    # ══════════════════════════════════════════════════════════════════════
    # NETWORK POLICIES
    # ══════════════════════════════════════════════════════════════════════
    kagent.NetworkPolicy.default-deny-all = {
      spec = {
        podSelector = {};
        policyTypes = ["Ingress" "Egress"];
      };
    };

    kagent.NetworkPolicy.allow-kagent-ingress = {
      metadata.labels = managed;
      spec = {
        podSelector.matchLabels = {"app.kubernetes.io/part-of" = "kagent";};
        policyTypes = ["Ingress"];
        ingress = [
          {
            from = [{namespaceSelector.matchLabels.name = "ingress-system";}];
            ports = [
              {
                protocol = "TCP";
                port = 8080;
              }
              {
                protocol = "TCP";
                port = 8083;
              }
            ];
          }
          {
            from = [{ipBlock.cidr = cluster.podCidr;}];
            ports = [
              {
                protocol = "TCP";
                port = 8080;
              }
              {
                protocol = "TCP";
                port = 8083;
              }
              {
                protocol = "TCP";
                port = 5432;
              }
            ];
          }
          {
            from = [{ipBlock.cidr = cluster.subnet;}];
            ports = [
              {
                protocol = "TCP";
                port = 8080;
              }
              {
                protocol = "TCP";
                port = 8083;
              }
            ];
          }
        ];
      };
    };

    kagent.NetworkPolicy.allow-kagent-egress = {
      metadata.labels = managed;
      spec = {
        podSelector.matchLabels = {"app.kubernetes.io/part-of" = "kagent";};
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

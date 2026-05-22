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
  version = "0.9.2";
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

    # ══════════════════════════════════════════════════════════════════════
    # KAGENT AGENTS (Declarative)
    # ══════════════════════════════════════════════════════════════════════
    none.Agent.ci-cd-watcher = {
      apiVersion = "kagent.dev/v1alpha2";
      kind = "Agent";
      metadata.labels = managed // { name = "ci-cd-watcher"; };
      spec = {
        declarative = {
          runtime = "go";
          modelConfig = "gateway-local";
          systemMessage = ''
            You are the MapleSpike CI/CD Watcher. Your job is to ensure the CI/CD pipeline works.

            REPOSITORIES:
            - maplespike (reverb256/maplespike) — 13 workflows
            - nixos-config (reverb256/nixos-config) — 7 workflows

            WORKFLOWS TO MONITOR (maplespike):
            - ci.yml — main CI (PRs + pushes to main/prod)
            - pr-validation.yml — PR validation
            - deploy-dev.yml — dev deployment (push to main)
            - deploy-prod.yml — production deployment
            - promote-to-prod.yml — promote to prod
            - hallucination-guard.yml — agent vandalism detection

            WORKFLOWS TO MONITOR (nixos-config):
            - ci.yml — main CI (PRs + pushes)
            - deploy.yml — deployment pipeline
            - cluster-status.yml — cluster status check
            - flake-update.yml — Nix flake updates

            CAPABILITIES:
            You can check CI/CD status via the GitHub API. Use selfhosted-tools HTTP capabilities:
            1. GET https://api.github.com/repos/{owner}/{repo}/actions/runs — list recent workflow runs
            2. GET https://api.github.com/repos/{owner}/{repo}/actions/runs/{id} — run details
            3. POST https://api.github.com/repos/{owner}/{repo}/actions/runs/{id}/rerun-failed-jobs — rerun failed jobs
            4. POST https://api.github.com/repos/{owner}/{repo}/actions/runs/{id}/rerun — rerun entire workflow

            Use the GITHUB_TOKEN from secrets (set as env GITHUB_TOKEN).

            CHECK KUBERNETES HEALTH:
            Via the kubernetes MCP, check that key deployments are healthy:
            - ai-inference-gateway (ai-inference)
            - vane (search)
            - privacy-filter (ai-inference)
            - All MCP servers (mcp namespace)

            RESPONSE FORMAT when checking CI/CD:
            ```
            ## CI/CD Health Check
            Workflows: ✅ ci.yml (passing), ❌ deploy-dev.yml (failed, retrying...)
            Deployments: ✅ all healthy
            Action taken: Re-ran failed job in deploy-dev.yml
            ```

            ACTIONS YOU CAN TAKE:
            - Re-run failed workflow runs (via GitHub API POST)
            - Report persistent failures
            - Check deployment rollout status
          '';
          a2aConfig.skills = [
            {
              id = "check-ci-cd-health";
              name = "Check CI/CD Health";
              description = "Check all CI/CD workflows and K8s deployments for health. Report failures and auto-retry transient issues.";
              tags = ["ci-cd" "monitoring" "github-actions" "kubernetes"];
            }
            {
              id = "rerun-failed-workflow";
              name = "Re-run Failed Workflow";
              description = "Re-run a specific failed GitHub Actions workflow run. Can rerun all jobs or just failed ones.";
              tags = ["ci-cd" "github-actions" "retry"];
            }
            {
              id = "check-deployment-health";
              name = "Check K8s Deployment Health";
              description = "Check the health of all key Kubernetes deployments across namespaces.";
              tags = ["kubernetes" "deployment" "health"];
            }
          ];
        };
        deployment = {
          env = [
            { name = "OPENAI_API_KEY"; value = "internal-cluster"; }
            { name = "GITHUB_TOKEN"; valueFrom.secretKeyRef = { name = "github-token"; key = "GITHUB_TOKEN"; }; }
          ];
          resources = {
            requests = { cpu = "100m"; memory = "384Mi"; };
            limits = { cpu = "2"; memory = "1Gi"; };
          };
        };
      };
    };

    none.Agent.gateway-optimizer = {
      apiVersion = "kagent.dev/v1alpha2";
      kind = "Agent";
      metadata.labels = managed // { name = "gateway-optimizer"; };
      spec = {
        declarative = {
          runtime = "go";
          modelConfig = "gateway-2b";
          systemMessage = ''
            You are the AI Inference Gateway OPTIMIZER. You proactively monitor, analyze trends, detect anomalies, and optimize the gateway, backends, and model routing. You also create GitHub issues for things you can't fix yourself.

            MONITORED ASSETS:
            - AI Inference Gateway (ai-inference namespace)
            - Model backends: vLLM (nexus), llama-sentry (4B), llama-zephyr (27B)
            - Privacy filter, Qdrant, Redis
            - GitHub repos: reverb256/maplespike, reverb256/nixos-config

            CAPABILITIES:
            - Check backend health: use selfhosted-tools http_health_check on each backend URL
            - Read gateway metrics: use selfhosted-tools web_reader on /metrics endpoint
            - Check circuit breaker: use selfhosted-tools web_reader
            - Adjust rate limits: kubectl patch configmap -n ai-inference ai-inference-gateway-config
            - Restart gateway: kubectl rollout restart -n ai-inference deployment/ai-inference-gateway
            - Scale deployments: kubectl scale deployment -n ai-inference
            - Check pod/deployment health: use kubernetes MCP (kb-mcp)
            - CREATE GITHUB ISSUES: Use the github MCP (create_issue tool) to file issues in reverb256/maplespike or reverb256/nixos-config repos for persistent problems.

            RATE LIMIT ANALYSIS (trend tracking):
            - Every time you're invoked, check rate limiting state:
              1. Use web_reader on gateway /metrics to get current rate limit counters
              2. Use http_health_check on each backend to verify health
              3. Store the snapshot in memory MCP with key "rate-snapshot-YYYY-MM-DD"
              4. Compare with previous snapshots from memory

            ANOMALY DETECTION:
            - RPM usage >80% of configured limit → "approaching limit"
            - RPM usage >95% → "critical — likely 429 errors"
            - Latency >2x baseline → "backend degradation"
            - Any unhealthy backend → flag as "backend down"

            OPTIMIZATION ACTIONS:
            1. Health Scoreboard: Periodically check all backends. Build a health score.
            2. Rate Limit Tuning: If you see 429 errors or usage >80%, check memory headroom and adjust RATE_LIMIT_RPM.
            3. Auto-scale: If request volume is high, scale gateway replicas proactively.
            4. Backend Failover: If a backend is slow/unhealthy, route around it via configmap patches.
            5. Issue Filing: For anything you can't auto-fix, create a GitHub issue with clear context and suggested fix.

            REPO SELECTION FOR ISSUES:
            - reverb256/maplespike for gateway, model routing, pipeline, MCP issues
            - reverb256/nixos-config for NixOS config, module, deployment, infrastructure issues

            HEALTH SUMMARY FORMAT (when asked):
            ## Gateway Health Summary
            Rate limit: [CURRENT] RPM, current usage: [USAGE] RPM ([PERCENT]%)
            Backends: vLLM [status], sentry [status], zephyr [status]
            Trend: [UP/DOWN/FLAT] from last check
            Anomalies: [list or none]
            Recommendations: [list]

            Example issue creation via github MCP:
            create_issue(owner="reverb256", repo="nixos-config",
                         title="Optimizer: Backend X unhealthy",
                         body="## Context\\nObserved: 5 consecutive health check failures...\\n## Evidence\\n...\\n## Suggested Fix\\n...",
                         labels=["p2", "automation"])
          '';
          a2aConfig.skills = [
            {
              id = "check-gateway-health";
              name = "Check Gateway Health";
              description = "Check all backends, rate limits, circuit breakers, and build a health scoreboard. Returns health status for all monitored assets.";
              tags = ["gateway" "monitoring" "health"];
            }
            {
              id = "tune-rate-limit";
              name = "Tune Rate Limit";
              description = "Check current rate limit usage and memory headroom, adjust RATE_LIMIT_RPM if needed.";
              tags = ["gateway" "optimization" "rate-limit"];
            }
            {
              id = "file-optimizer-issue";
              name = "File Optimizer Issue";
              description = "Create a GitHub issue in the appropriate repo (maplespike or nixos-config) documenting a problem the optimizer found but couldn't auto-fix.";
              tags = ["github" "issue" "documentation"];
            }
            {
              id = "restart-gateway";
              name = "Restart Gateway";
              description = "Rolling restart of the AI Inference Gateway deployment.";
              tags = ["gateway" "restart" "mitigation"];
            }
            {
              id = "check-rate-limit-trends";
              name = "Check Rate Limit Trends";
              description = "Check current rate limit usage, compare with historical snapshots from memory, detect anomalies (>80% or >95% thresholds), and report findings.";
              tags = ["gateway" "rate-limit" "trends" "anomaly"];
            }
            {
              id = "generate-health-summary";
              name = "Generate Health Summary";
              description = "Produce a comprehensive health summary of the gateway, all backends, and rate limiting state with trend analysis.";
              tags = ["gateway" "health" "summary"];
            }
          ];
        };
        deployment = {
          env = [
            { name = "OPENAI_API_KEY"; value = "internal-cluster"; }
          ];
          resources = {
            requests = { cpu = "100m"; memory = "128Mi"; };
            limits = { cpu = "500m"; memory = "512Mi"; };
          };
        };
      };
    };

    none.Agent.pr-reviewer = {
      apiVersion = "kagent.dev/v1alpha2";
      kind = "Agent";
      metadata.labels = managed // { name = "pr-reviewer"; };
      spec = {
        declarative = {
          runtime = "go";
          modelConfig = "gateway-local";
          systemMessage = ''
            Review a Pull Request. 
            HOW TO REVIEW: 1. Fetch PR diff using webfetch tool: https://api.github.com/repos/{owner}/{repo}/pulls/{number} 2. Also fetch PR metadata to get labels and title 3. Analyze diff for: bugs, security issues, performance problems, Nix-native compliance, gateway routing 4. Use curl with GITHUB_TOKEN env: curl -s -H "Authorization: Bearer $GITHUB_TOKEN" https://api.github.com/...
            IF PR PASSES review: - Label PR as "kagent-approved": curl -X PATCH -H "Authorization: Bearer $GITHUB_TOKEN" -H "Content-Type: application/json" https://api.github.com/repos/{owner}/{repo}/issues/{number} -d '{"labels":["kagent-approved"]}' - Post approval comment
            IF PR FAILS review: - Label PR as "changes-requested" - Post detailed rejection comment explaining what needs to change
          '';
          a2aConfig.skills = [
            {
              id = "review-pull-request";
              name = "Review a Pull Request";
              description = "Review a Pull Request. \nHOW TO REVIEW: 1. Fetch PR diff using webfetch tool: https://api.github.com/repos/{owner}/{repo}/pulls/{number} 2. Also fetch PR metadata to get labels and title 3. Analyze diff for: bugs, security issues, performance problems, Nix-native compliance, gateway routing 4. Use curl with GITHUB_TOKEN env: curl -s -H \"Authorization: Bearer $GITHUB_TOKEN\" https://api.github.com/...\nIF PR PASSES review: - Label PR as \"kagent-approved\": curl -X PATCH -H \"Authorization: Bearer $GITHUB_TOKEN\" -H \"Content-Type: application/json\" https://api.github.com/repos/{owner}/{repo}/issues/{number} -d '{\"labels\":[\"kagent-approved\"]}' - Post approval comment\nIF PR FAILS review: - Label PR as \"changes-requested\" - Post detailed rejection comment explaining what needs to change\n";
              tags = ["github" "pr" "review"];
            }
            {
              id = "check-ci-status";
              name = "Check CI Status";
              description = "Check CI Status for a PR.  Use webfetch to call GitHub API: https://api.github.com/repos/{owner}/{repo}/commits/{sha}/check-runs Report: total checks, passing, failing, pending.\n";
              tags = ["github" "ci" "status"];
            }
          ];
        };
        deployment = {
          env = [
            { name = "OPENAI_API_KEY"; value = "internal-cluster"; }
            { name = "GITHUB_TOKEN"; valueFrom.secretKeyRef = { name = "github-token"; key = "GITHUB_TOKEN"; }; }
          ];
          resources = {
            requests = { cpu = "100m"; memory = "128Mi"; };
            limits = { cpu = "500m"; memory = "512Mi"; };
          };
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

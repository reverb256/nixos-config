{
  cluster,
  config,
  lib,
  ...
}: let
  # ── Version pinning ──────────────────────────────────────────────────
  version = "v0.33.0";
  registry = "ghcr.io/kelos-dev";

  # ── Image references ─────────────────────────────────────────────────
  controllerImage = "${registry}/kelos-controller:${version}";

  # ── Cluster placement ────────────────────────────────────────────────
  targetNode = "nexus";
  ns = "kelos-system";

  # ── Labels ───────────────────────────────────────────────────────────
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
    "app.kubernetes.io/part-of" = "kelos";
  };

  # ── Workspace base spec ──────────────────────────────────────────────
  mkWorkspace = name: repo: {
    apiVersion = "kelos.dev/v1alpha1";
    kind = "Workspace";
    metadata = {
      inherit name;
      labels = managed;
    };
    spec = {
      repo = "https://github.com/reverb256/${repo}.git";
      ref = "main";
      secretRef.name = "github-token";
      setupCommand = ["sh" "-c" "chmod -R g+rw /workspace/repo"];
    };
  };

  # ── Task base spec ──────────────────────────────────────────────────
  taskOverrides = {
    podSecurityContext = {
      runAsNonRoot = true;
      runAsUser = 1000;
      runAsGroup = 1000;
      fsGroup = 1000;
    };
    resources = {
      requests = { cpu = "250m"; memory = "512Mi"; };
      limits = { cpu = "1"; memory = "1Gi"; };
    };
    containerSecurityContext = {
      runAsNonRoot = true;
      allowPrivilegeEscalation = false;
      capabilities.drop = ["ALL"];
      seccompProfile.type = "RuntimeDefault";
    };
  };

  # ── TaskSpawner generator ────────────────────────────────────────────
  mkTaskSpawner = name: repo: workspace: {
    apiVersion = "kelos.dev/v1alpha1";
    kind = "TaskSpawner";
    metadata = {
      inherit name;
      labels = managed;
    };
    spec = {
      when.githubIssues = {
        repo = "reverb256/${repo}";
        labels = ["agent-ready"];
        state = "open";
        pollInterval = "5m";
      };
      taskTemplate = {
        type = "opencode";
        credentials = {
          type = "api-key";
          secretRef.name = "opencode-credentials";
        };
        workspaceRef.name = workspace;
        agentConfigRef.name = "cluster-coder";
        branch = "kelos-task-{{.Number}}";
        promptTemplate = ''
          GitHub issue #{{.Number}}: {{.Title}}

          Description:
          {{.Body}}

          Implement the required changes on branch issue-{{.Number}}-{{.Title | lower | replace " " "-" | trunc 40}},
          push the branch, and open a PR against main.
          Every commit message must include #{{.Number}}.
        '';
        ttlSecondsAfterFinished = 3600;
        podOverrides = {
          podSecurityContext = {
            runAsNonRoot = true;
            runAsUser = 1000;
            runAsGroup = 1000;
            fsGroup = 1000;
          };
          resources = {
            requests = { cpu = "250m"; memory = "512Mi"; };
            limits = { cpu = "1"; memory = "1Gi"; };
          };
          containerSecurityContext = {
            runAsNonRoot = true;
            allowPrivilegeEscalation = false;
            capabilities.drop = ["ALL"];
            seccompProfile.type = "RuntimeDefault";
          };
        };
      };
      maxConcurrency = 2;
    };
  };

  # ── Workspace list ───────────────────────────────────────────────────
  workspaceList = [
    { name = "nixos-config"; repo = "nixos-config"; }
    { name = "ai-inference-gateway"; repo = "ai-inference-gateway"; }
    { name = "maplespike"; repo = "maplespike"; }
    { name = "knowledge-fabric"; repo = "knowledge-fabric"; }
    { name = "compute-market"; repo = "compute-market"; }
    { name = "mcp-registry"; repo = "mcp-registry"; }
    { name = "gpu-proxy"; repo = "gpu-proxy"; }
    { name = "llama-cpp-turboquant"; repo = "llama-cpp-turboquant"; }
    { name = "vllm-turboquant"; repo = "vllm-turboquant"; }
    { name = "searxng-cluster"; repo = "searxng-cluster"; }
    { name = "caddy-ingress"; repo = "caddy-ingress"; }
    { name = "vane"; repo = "Vane"; }
  ];

  # ── Build workspace resources ────────────────────────────────────────
  workspaceResources = builtins.listToAttrs (map (w: {
    name = "${ns}.Resource.workspace-${w.name}";
    value = mkWorkspace w.name w.repo;
  }) workspaceList);

  # ── Build TaskSpawner resources ──────────────────────────────────────
  spawnerResources = builtins.listToAttrs (map (w: {
    name = "${ns}.Resource.taskspawner-${w.name}";
    value = mkTaskSpawner "github-issues-${w.name}" w.repo w.name;
  }) workspaceList);

in {
  config.kubernetes.objects =
    {
      # ══════════════════════════════════════════════════════════════════
      # NAMESPACE
      # ══════════════════════════════════════════════════════════════════
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

      # ══════════════════════════════════════════════════════════════════
      # SERVICE ACCOUNT
      # ══════════════════════════════════════════════════════════════════
      ${ns}.ServiceAccount.kelos-controller = {
        metadata.labels = managed;
      };

      # ══════════════════════════════════════════════════════════════════
      # RBAC
      # ══════════════════════════════════════════════════════════════════
      none.ClusterRole.kelos-controller = {
        metadata.labels = managed;
        rules = [
          {
            apiGroups = [""];
            resources = [
              "pods" "pods/log" "pods/status"
              "secrets" "configmaps" "serviceaccounts" "services"
              "events" "namespaces"
            ];
            verbs = ["get" "list" "watch" "create" "update" "patch" "delete"];
          }
          {
            apiGroups = ["apps"];
            resources = ["deployments" "deployments/status" "deployments/scale" "replicasets" "statefulsets"];
            verbs = ["get" "list" "watch" "create" "update" "patch" "delete"];
          }
          {
            apiGroups = ["batch"];
            resources = ["jobs" "jobs/status" "cronjobs"];
            verbs = ["get" "list" "watch" "create" "update" "patch" "delete"];
          }
          {
            apiGroups = ["kelos.dev"];
            resources = ["tasks" "tasks/status" "tasks/finalizers" "workspaces" "workspaces/status" "agentconfigs" "agentconfigs/status" "taskspawners" "taskspawners/status"];
            verbs = ["get" "list" "watch" "create" "update" "patch" "delete"];
          }
          {
            apiGroups = ["rbac.authorization.k8s.io"];
            resources = ["roles" "rolebindings" "clusterroles" "clusterrolebindings"];
            verbs = ["get" "list" "watch" "create" "update" "patch" "delete"];
          }
          {
            apiGroups = ["coordination.k8s.io"];
            resources = ["leases"];
            verbs = ["get" "list" "watch" "create" "update" "patch" "delete"];
          }
          {
            apiGroups = ["networking.k8s.io"];
            resources = ["networkpolicies"];
            verbs = ["get" "list" "watch" "create" "update" "patch" "delete"];
          }
        ];
      };

      none.ClusterRoleBinding.kelos-controller = {
        metadata.labels = managed;
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "kelos-controller";
        };
        subjects = [
          {
            kind = "ServiceAccount";
            name = "kelos-controller";
            namespace = ns;
          }
        ];
      };

      # ══════════════════════════════════════════════════════════════════
      # CONTROLLER DEPLOYMENT
      # ══════════════════════════════════════════════════════════════════
      ${ns}.Deployment.kelos-controller-manager = {
        metadata.labels = managed // {"app.kubernetes.io/component" = "controller";};
        spec = {
          replicas = 1;
          revisionHistoryLimit = 2;
          strategy.type = "Recreate";
          selector.matchLabels = {"control-plane" = "controller-manager";};
          template = {
            metadata.labels = {"control-plane" = "controller-manager";};
            spec = {
              nodeSelector."kubernetes.io/hostname" = targetNode;
              serviceAccountName = "kelos-controller";
              securityContext = {
                runAsNonRoot = true;
                seccompProfile.type = "RuntimeDefault";
              };
              containers._namedlist = true;
              containers.manager = {
                image = controllerImage;
                imagePullPolicy = "IfNotPresent";
                command = ["/manager"];
                args = [
                  "--leader-elect"
                  "--health-probe-bind-address=:8081"
                  "--metrics-bind-address=127.0.0.1:8080"
                ];
                ports._namedlist = true;
                ports.http = { containerPort = 9443; protocol = "TCP"; };
                env._namedlist = true;
                env = {
                  KELOS_NAMESPACE.valueFrom.fieldRef.fieldPath = "metadata.namespace";
                  IMAGE_PULL_POLICY.value = "IfNotPresent";
                  SPAWNER_IMAGE.value = "${registry}/opencode:${version}";
                  AGENT_TYPE.value = "opencode";
                };
                resources = {
                  requests = { cpu = "100m"; memory = "128Mi"; };
                  limits = { cpu = "500m"; memory = "256Mi"; };
                };
                securityContext = {
                  allowPrivilegeEscalation = false;
                  capabilities.drop = ["ALL"];
                  readOnlyRootFilesystem = true;
                  seccompProfile.type = "RuntimeDefault";
                  runAsNonRoot = true;
                };
                livenessProbe = {
                  httpGet = { path = "/healthz"; port = 8081; };
                  initialDelaySeconds = 15;
                  periodSeconds = 20;
                };
                readinessProbe = {
                  httpGet = { path = "/readyz"; port = 8081; };
                  initialDelaySeconds = 5;
                  periodSeconds = 10;
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

      # ══════════════════════════════════════════════════════════════════
      # AGENT CONFIG
      # ══════════════════════════════════════════════════════════════════
      ${ns}.Resource.agentconfig-cluster-coder = {
        apiVersion = "kelos.dev/v1alpha1";
        kind = "AgentConfig";
        metadata = {
          name = "cluster-coder";
          labels = managed;
        };
        spec = {
          agentsMD = ''
            # NixOS Cluster — Agent Guidelines (via Kelos)

            You were spawned by Kelos because this issue has the "agent-ready" label.

            ## Cluster Overview
            - 4 nodes: Zephyr (31GB), Nexus (46GB), Forge (16GB), Sentry (31GB)
            - K3s cluster with Flannel CNI
            - AI Inference Gateway at 10.15.67.242:8080

            ## Model
            - deepseek-v4-flash (fast, 1M context) — default for most tasks
            - Use it efficiently: small context windows for simple edits

            ## Critical Rules
            - lib.mkOptionDefault for all list/attr options in Nix
            - Default ALL workloads to Nexus (46GB) — avoid Zephyr OOM
            - GPU NOT isolated per-pod — nvidia-container-runtime broken on NixOS
            - Stop if SSH breaks or `nix flake check` fails

            ## Workflow
            - Implement the issue, push branch, open PR against main
            - Branch: issue-NNN-short-description
            - Every commit references #NNN
            - PR body: "Closes #NNN"
          '';
          mcpServers = [];
        };
      };

      # ══════════════════════════════════════════════════════════════════
      # SECRETS
      # ══════════════════════════════════════════════════════════════════
      ${ns}.Secret.opencode-credentials = {
        type = "Opaque";
        # Populate via: kubectl create secret generic -n kelos-system opencode-credentials
        #   --from-literal=OPENCODE_API_KEY="${YOUR_KEY}"
      };
      ${ns}.Secret.github-token = {
        type = "Opaque";
        # Populate via: kubectl create secret generic -n kelos-system github-token
        #   --from-literal=GITHUB_TOKEN="${YOUR_TOKEN}"
      };

      # ══════════════════════════════════════════════════════════════════
      # WORKSPACES (one per active repo)
      # ══════════════════════════════════════════════════════════════════
    }
    // workspaceResources
    // spawnerResources
  ;
}

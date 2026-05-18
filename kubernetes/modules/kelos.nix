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

  # ── Shared pod overrides ─────────────────────────────────────────────
  podOverrides = {
    podSecurityContext = {
      runAsNonRoot = true;
      runAsUser = 61100;
      runAsGroup = 61100;
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

  # ── Workspace factory ────────────────────────────────────────────────
  mkWorkspace = name: repo: {
    apiVersion = "kelos.dev/v1alpha1";
    kind = "Workspace";
    metadata = { inherit name; labels = managed; };
    spec = {
      repo = "https://github.com/reverb256/${repo}.git";
      ref = "main";
      secretRef.name = "github-token";
      setupCommand = ["sh" "-c" "chmod -R g+rw /workspace/repo"];
    };
  };

  # ── Prompt templates by label type ───────────────────────────────────
  promptTemplates = {
    bug = ''
      GitHub issue #{{.Number}}: {{.Title}}

      Description:
      {{.Body}}

      This is a BUG fix. Focus on:
      - Identifying and fixing the root cause
      - Adding tests to verify the fix and prevent regression
      - Verifying the fix works as expected

      Implement the required changes, push the branch, and open a PR against main.
      Branch: kelos-task-{{.Number}}
      Every commit message must include #{{.Number}}.
      The workspace at /workspace/repo is writable — work directly there.
    '';

    enhancement = ''
      GitHub issue #{{.Number}}: {{.Title}}

      Description:
      {{.Body}}

      This is an ENHANCEMENT. Focus on:
      - Clean implementation following existing patterns
      - Adding documentation for new functionality
      - Considering edge cases and error handling

      Implement the required changes, push the branch, and open a PR against main.
      Branch: kelos-task-{{.Number}}
      Every commit message must include #{{.Number}}.
      The workspace at /workspace/repo is writable — work directly there.
    '';

    security = ''
      GitHub issue #{{.Number}}: {{.Title}}

      Description:
      {{.Body}}

      This is a SECURITY issue. Focus on:
      - Hardening the code against vulnerabilities
      - Auditing for potential security issues
      - Adding security-focused tests

      Implement the required changes, push the branch, and open a PR against main.
      Branch: kelos-task-{{.Number}}
      Every commit message must include #{{.Number}}.
      The workspace at /workspace/repo is writable — work directly there.
    '';

    refactor = ''
      GitHub issue #{{.Number}}: {{.Title}}

      Description:
      {{.Body}}

      This is a REFACTOR. Focus on:
      - Improving code structure and maintainability
      - Maintaining backward compatibility
      - Preserving existing behavior while improving internals

      Implement the required changes, push the branch, and open a PR against main.
      Branch: kelos-task-{{.Number}}
      Every commit message must include #{{.Number}}.
      The workspace at /workspace/repo is writable — work directly there.
    '';

    cleanup = ''
      GitHub issue #{{.Number}}: {{.Title}}

      Description:
      {{.Body}}

      This is a CLEANUP task. Focus on:
      - Making minimal, targeted changes
      - Not breaking existing behavior
      - Removing dead code, fixing formatting, or simplifying logic

      Implement the required changes, push the branch, and open a PR against main.
      Branch: kelos-task-{{.Number}}
      Every commit message must include #{{.Number}}.
      The workspace at /workspace/repo is writable — work directly there.
    '';
  };

  # ── TaskSpawner factory (multi-label) ────────────────────────────────
  mkSpawner = name: repo: workspace: labelType: promptTemplate: {
    apiVersion = "kelos.dev/v1alpha1";
    kind = "TaskSpawner";
    metadata = { name = "github-issues-${name}"; labels = managed; };
    spec = {
      when.githubIssues = {
        repo = "reverb256/${repo}";
        labels = ["agent-ready" labelType];
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
        inherit promptTemplate;
        ttlSecondsAfterFinished = 3600;
        inherit podOverrides;
      };
      maxConcurrency = 2;
    };
  };

  # ── Label types ──────────────────────────────────────────────────────
  labelTypes = [ "bug" "enhancement" "security" "refactor" "cleanup" ];

  # ── Repos ────────────────────────────────────────────────────────────
  repos = [
    { name = "nixos-config"; workspace = "nixos-config"; }
    { name = "ai-inference-gateway"; workspace = "ai-inference-gateway"; }
    { name = "maplespike"; workspace = "maplespike"; }
    { name = "knowledge-fabric"; workspace = "knowledge-fabric"; }
    { name = "compute-market"; workspace = "compute-market"; }
    { name = "mcp-registry"; workspace = "mcp-registry"; }
    { name = "gpu-proxy"; workspace = "gpu-proxy"; }
    { name = "llama-cpp-turboquant"; workspace = "llama-cpp-turboquant"; }
    { name = "vllm-turboquant"; workspace = "vllm-turboquant"; }
    { name = "searxng-cluster"; workspace = "searxng-cluster"; }
    { name = "caddy-ingress"; workspace = "caddy-ingress"; }
    { name = "vane"; workspace = "vane"; }
  ];

  # ── Generate all spawner resources ───────────────────────────────────
  allSpawners = lib.listToAttrs (
    lib.concatMap (r:
      lib.concatMap (labelType:
        let name = "${r.name}-${labelType}"; in
        [{
          name = "taskspawner-${name}";
          value = mkSpawner name r.name r.workspace labelType promptTemplates.${labelType};
        }]
      ) labelTypes
    ) repos
  );
in {
  config.kubernetes.objects = {
    # ════════════════════════════════════════════════════════════════════
    # CLUSTER-SCOPED RESOURCES (none namespace)
    # ════════════════════════════════════════════════════════════════════
    none = {
      Namespace.${ns} = {
        metadata.labels = { name = ns; } // managed;
      };

      ClusterRole."kelos-controller" = {
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

      ClusterRoleBinding."kelos-controller" = {
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
    };

    # ════════════════════════════════════════════════════════════════════
    # NAMESPACE-SCOPED RESOURCES (kelos-system)
    # ════════════════════════════════════════════════════════════════════
    # IMPORTANT: Nix forbids multiple ${ns} dynamic attribute keys at the
    # same scope level. All namespace resources must be in ONE block.
    ${ns} = {
      # ── Service account ───────────────────────────
      ServiceAccount."kelos-controller" = {
        metadata.labels = managed;
      };

      # ── Secrets ───────────────────────────────────
      Secret."opencode-credentials" = { type = "Opaque"; };
      Secret."github-token" = { type = "Opaque"; };

      # ── Controller deployment ─────────────────────
      Deployment."kelos-controller-manager" = {
        metadata.labels = managed // { "app.kubernetes.io/component" = "controller"; };
        spec = {
          replicas = 1;
          revisionHistoryLimit = 2;
          strategy.type = "Recreate";
          selector.matchLabels = { "control-plane" = "controller-manager"; };
          template = {
            metadata.labels = { "control-plane" = "controller-manager"; };
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

      # ── Resources: agentconfig, workspaces, spawners ──
      Resource = {
        # ── Agent config ──────────────────────────────
        "agentconfig-cluster-coder" = {
          apiVersion = "kelos.dev/v1alpha1";
          kind = "AgentConfig";
          metadata = { name = "cluster-coder"; labels = managed; };
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

              ## Critical Rules
              - lib.mkOptionDefault for all list/attr options in Nix
              - Default ALL workloads to Nexus (46GB) — avoid Zephyr OOM
              - GPU NOT isolated per-pod — nvidia-container-runtime broken on NixOS
              - Stop if SSH breaks or `nix flake check` fails

              ## Workflow
              - The workspace at /workspace/repo is writable
              - Implement the issue, push branch, open PR against main
              - Branch: kelos-task-NNN
              - Every commit references #NNN
              - PR body: "Closes #NNN"
            '';
            mcpServers = [];
          };
        };

        # ── Workspaces (12 repos) ────────────────────
        "workspace-nixos-config" = mkWorkspace "nixos-config" "nixos-config";
        "workspace-ai-inference-gateway" = mkWorkspace "ai-inference-gateway" "ai-inference-gateway";
        "workspace-maplespike" = mkWorkspace "maplespike" "maplespike";
        "workspace-knowledge-fabric" = mkWorkspace "knowledge-fabric" "knowledge-fabric";
        "workspace-compute-market" = mkWorkspace "compute-market" "compute-market";
        "workspace-mcp-registry" = mkWorkspace "mcp-registry" "mcp-registry";
        "workspace-gpu-proxy" = mkWorkspace "gpu-proxy" "gpu-proxy";
        "workspace-llama-cpp-turboquant" = mkWorkspace "llama-cpp-turboquant" "llama-cpp-turboquant";
        "workspace-vllm-turboquant" = mkWorkspace "vllm-turboquant" "vllm-turboquant";
        "workspace-searxng-cluster" = mkWorkspace "searxng-cluster" "searxng-cluster";
        "workspace-caddy-ingress" = mkWorkspace "caddy-ingress" "caddy-ingress";
        "workspace-vane" = mkWorkspace "vane" "Vane";
      } // allSpawners;
    };
  };
}

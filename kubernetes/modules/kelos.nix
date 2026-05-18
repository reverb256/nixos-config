{
  cluster,
  config,
  lib,
  ...
}: let
  # ── Version pinning ──────────────────────────────────────────────────
  # Kelos v0.33.0 (2026-05-18) — latest stable release
  # Registry: ghcr.io/kelos-dev (GitHub Container Registry)
  # Check: https://github.com/kelos-dev/kelos/releases
  version = "v0.33.0";
  registry = "ghcr.io/kelos-dev";

  # ── Image references ─────────────────────────────────────────────────
  controllerImage = "${registry}/kelos-controller:${version}";

  # ── Cluster placement ────────────────────────────────────────────────
  # All Kelos components on Nexus (46GB RAM, control plane)
  targetNode = "nexus";
  ns = "kelos-system";

  # ── Labels ───────────────────────────────────────────────────────────
  managed = {
    "app.kubernetes.io/managed-by" = "easykubenix";
    "app.kubernetes.io/part-of" = "kelos";
  };
in {
  config.kubernetes.objects = {
    # ══════════════════════════════════════════════════════════════════════
    # NAMESPACE
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
    # SERVICE ACCOUNT
    # ══════════════════════════════════════════════════════════════════════
    ${ns}.ServiceAccount.kelos-controller = {
      metadata.labels = managed;
    };

    # ══════════════════════════════════════════════════════════════════════
    # RBAC — Controller needs cluster-wide CRD and pod management
    # ══════════════════════════════════════════════════════════════════════
    none.ClusterRole.kelos-controller = {
      metadata.labels = managed;
      rules = [
        # Core resources
        {
          apiGroups = [""];
          resources = [
            "pods"
            "pods/log"
            "pods/status"
            "secrets"
            "configmaps"
            "serviceaccounts"
            "services"
            "events"
            "namespaces"
          ];
          verbs = ["get" "list" "watch" "create" "update" "patch" "delete"];
        }
        # Apps resources
        {
          apiGroups = ["apps"];
          resources = ["deployments" "deployments/status" "deployments/scale" "replicasets" "statefulsets"];
          verbs = ["get" "list" "watch" "create" "update" "patch" "delete"];
        }
        # Batch resources (for task pods)
        {
          apiGroups = ["batch"];
          resources = ["jobs" "jobs/status" "cronjobs"];
          verbs = ["get" "list" "watch" "create" "update" "patch" "delete"];
        }
        # Kelos CRDs
        {
          apiGroups = ["kelos.dev"];
          resources = ["tasks" "tasks/status" "tasks/finalizers" "workspaces" "workspaces/status" "agentconfigs" "agentconfigs/status" "taskspawners" "taskspawners/status"];
          verbs = ["get" "list" "watch" "create" "update" "patch" "delete"];
        }
        # RBAC (for spawning agent pods with service accounts)
        {
          apiGroups = ["rbac.authorization.k8s.io"];
          resources = ["roles" "rolebindings" "clusterroles" "clusterrolebindings"];
          verbs = ["get" "list" "watch" "create" "update" "patch" "delete"];
        }
        # Coordination (leader election)
        {
          apiGroups = ["coordination.k8s.io"];
          resources = ["leases"];
          verbs = ["get" "list" "watch" "create" "update" "patch" "delete"];
        }
        # Networking
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

    # ══════════════════════════════════════════════════════════════════════
    # CONTROLLER DEPLOYMENT
    # ══════════════════════════════════════════════════════════════════════
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
              ports.http = {
                containerPort = 9443;
                protocol = "TCP";
              };
              env._namedlist = true;
              env = {
                KELOS_NAMESPACE.valueFrom.fieldRef.fieldPath = "metadata.namespace";
                IMAGE_PULL_POLICY.value = "IfNotPresent";
                SPAWNER_IMAGE.value = "${registry}/opencode:${version}";
                # Default OpenCode agent configuration
                AGENT_TYPE.value = "opencode";
              };
              resources = {
                requests = {
                  cpu = "100m";
                  memory = "128Mi";
                };
                limits = {
                  cpu = "500m";
                  memory = "256Mi";
                };
              };
              securityContext = {
                allowPrivilegeEscalation = false;
                capabilities.drop = ["ALL"];
                readOnlyRootFilesystem = true;
                seccompProfile.type = "RuntimeDefault";
                runAsNonRoot = true;
              };
              livenessProbe = {
                httpGet = {
                  path = "/healthz";
                  port = 8081;
                };
                initialDelaySeconds = 15;
                periodSeconds = 20;
              };
              readinessProbe = {
                httpGet = {
                  path = "/readyz";
                  port = 8081;
                };
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

    # ══════════════════════════════════════════════════════════════════════
    # AGENT CONFIG — cluster agent with context/instructions
    # ══════════════════════════════════════════════════════════════════════
    ${ns}.Resource.agentconfig-cluster-coder = {
      apiVersion = "kelos.dev/v1alpha1";
      kind = "AgentConfig";
      metadata = {
        name = "cluster-coder";
        labels = managed;
      };
      spec = {
        agentsMD = ''
          # NixOS Cluster - Agent Guidelines (via Kelos)

          ## Cluster Overview
          - 4 nodes: Zephyr (31GB), Nexus (46GB), Forge (16GB), Sentry (31GB)
          - K3s cluster with Flannel CNI
          - AI Inference Gateway at 10.15.67.242:8080
          - All configs in /etc/nixos/ (source of truth)

          ## Critical Rules
          - lib.mkOptionDefault for all list/attr options
          - Default ALL workloads to Nexus (46GB RAM) - avoid Zephyr OOM
          - GPU is NOT isolated per-pod (nvidia-container-runtime broken on NixOS)
          - Stop immediately if SSH breaks or nix flake check fails

          ## Workflow
          - ALL changes through PRs: issue → branch → PR → merge → close
          - Worktrees on /data/projects/own/
        '';
        mcpServers = [];
      };
    };

    # ══════════════════════════════════════════════════════════════════════
    # TASK SPAWNER — GitHub Issues → Auto-Create Tasks
    # ══════════════════════════════════════════════════════════════════════
    ${ns}.Resource.taskspawner-github-issues = {
      apiVersion = "kelos.dev/v1alpha1";
      kind = "TaskSpawner";
      metadata = {
        name = "github-issues";
        labels = managed;
      };
      spec = {
        when.githubIssues = {
          repo = "reverb256/nixos-config";
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
          workspaceRef.name = "nixos-config";
          agentConfigRef.name = "cluster-coder";
          branch = "kelos-task-{{.Number}}";
          promptTemplate = ''
            GitHub issue #{{.Number}}: {{.Title}}

            Description:
            {{.Body}}

            Create a branch named issue-{{.Number}}-{{.Title | lower | replace " " "-" | trunc 30}},
            implement the required changes, push the branch, and open a PR against main.
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
              requests = {
                cpu = "250m";
                memory = "512Mi";
              };
              limits = {
                cpu = "1";
                memory = "1Gi";
              };
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
    # Credential secret for OpenCode agent
    ${ns}.Secret.opencode-credentials = {
      type = "Opaque";
      # Populate via agenix or manual secret creation:
      # kubectl create secret generic -n kelos-system opencode-credentials \
      #   --from-literal=OPENCODE_API_KEY="${YOUR_OPENCODE_KEY}"
    };
    # GitHub token for workspace git operations
    ${ns}.Secret.github-token = {
      type = "Opaque";
      # Populate via agenix or manual secret creation:
      # kubectl create secret generic -n kelos-system github-token \
      #   --from-literal=GITHUB_TOKEN="${YOUR_GITHUB_TOKEN}"
    };

    # ══════════════════════════════════════════════════════════════════════
    # WORKSPACE RESOURCES (git repos agents operate on)
    # ══════════════════════════════════════════════════════════════════════
    ${ns}.Resource.workspace-nixos-config = {
      apiVersion = "kelos.dev/v1alpha1";
      kind = "Workspace";
      metadata = {
        name = "nixos-config";
        labels = managed;
      };
      spec = {
        repo = "https://github.com/reverb256/nixos-config.git";
        ref = "main";
        secretRef.name = "github-token";
        setupCommand = ["sh" "-c" "chown -R 1000:1000 /workspace/repo"];
      };
    };
    ${ns}.Resource.workspace-ai-inference = {
      apiVersion = "kelos.dev/v1alpha1";
      kind = "Workspace";
      metadata = {
        name = "ai-inference-gateway";
        labels = managed;
      };
      spec = {
        repo = "https://github.com/reverb256/ai-inference-gateway.git";
        ref = "main";
        secretRef.name = "github-token";
        setupCommand = ["sh" "-c" "chown -R 1000:1000 /workspace/repo"];
      };
    };
    ${ns}.Resource.workspace-maplespike = {
      apiVersion = "kelos.dev/v1alpha1";
      kind = "Workspace";
      metadata = {
        name = "maplespike";
        labels = managed;
      };
      spec = {
        repo = "https://github.com/reverb256/maplespike.git";
        ref = "main";
        secretRef.name = "github-token";
        setupCommand = ["sh" "-c" "chown -R 1000:1000 /workspace/repo"];
      };
    };
  };
}

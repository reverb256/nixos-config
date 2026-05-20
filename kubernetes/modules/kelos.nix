# Kelos task orchestration module.
# Controller self-manages Workspaces, TaskSpawners, AgentConfigs.
# This module bootstraps the initial config and provides fallback definitions.
# See: https://github.com/reverb256/kelos-controller
{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.kubernetes.kelos;
  inherit (cfg) repo;

  # Shared opencode.json config with NIM models via AI Inference Gateway
  opencodeConfig = lib.generators.toJSON {} {
    "$schema" = "https://opencode.ai/config.json";
    model = "openai/nvidia/nemotron-3-super-120b-a12b";
    enabled_providers = ["openai"];
    provider.openai = {
      options = {
        baseURL = "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1";
        apiKey = "\$OPENCODE_API_KEY";
      };
      models = {
        "openai/nvidia/nemotron-3-super-120b-a12b" = {
          context_length = 131072;
          max_tokens = 16384;
          id = "openai/nvidia/nemotron-3-super-120b-a12b";
          name = "openai/nvidia/nemotron-3-super-120b-a12b";
        };
        "openai/nvidia/nemotron-3-super-120b-a12b:free" = {
          context_length = 131072;
          max_tokens = 16384;
          id = "openai/nvidia/nemotron-3-super-120b-a12b:free";
          name = "openai/nvidia/nemotron-3-super-120b-a12b:free";
        };
        "nvidia/llama-3.3-nemotron-super-49b-v1" = {
          context_length = 131072;
          max_tokens = 16384;
          id = "nvidia/llama-3.3-nemotron-super-49b-v1";
          name = "nvidia/llama-3.3-nemotron-super-49b-v1";
        };
      };
    };
  };

  # Shared setup command for all Workspaces
  setupCommand = ["/bin/sh" "-c" ''
    chmod -R g+rw /workspace/repo && cat > /workspace/repo/opencode.json << 'EOFOP'
    ${opencodeConfig}
    EOFOP
  ''];

  # Repos that get Kelos task automation
  repos = [
    "ai-inference-gateway"
    "caddy-ingress"
    "compute-market"
    "gpu-proxy"
    "knowledge-fabric"
    "llama-cpp-turboquant"
    "maplespike"
    "mcp-registry"
    "nixos-config"
    "searxng-cluster"
    "vane"
    "vllm-turboquant"
  ];

  # Create a workspace for each repo
  workspaces = map (r: {
    apiVersion = "kelos.dev/v1alpha1";
    kind = "Workspace";
    metadata = {
      name = r;
      namespace = "kelos-system";
      labels = {
        "app.kubernetes.io/managed-by" = "easykubenix";
        "app.kubernetes.io/part-of" = "kelos";
      };
    };
    spec = {
      repo = "https://github.com/reverb256/${r}.git";
      ref = "main";
      secretRef.name = "github-token";
      files = [];
      inherit setupCommand;
    };
  }) repos;

  # TaskSpawner template applied per repo
  taskSpawnerTemplate = r: {
    apiVersion = "kelos.dev/v1alpha1";
    kind = "TaskSpawner";
    metadata = {
      name = "github-issues-${r}";
      namespace = "kelos-system";
      labels = {
        "app.kubernetes.io/managed-by" = "easykubenix";
        "app.kubernetes.io/part-of" = "kelos";
      };
    };
    spec = {
      maxConcurrency = 2;
      taskTemplate = {
        type = "opencode";
        workspaceRef.name = r;
        agentConfigRef.name = "cluster-coder";
        branch = "kelos-task-\{\{.Number\}\}";
        credentials = {
          type = "api-key";
          secretRef.name = "opencode-credentials";
        };
        promptTemplate = ''
          GitHub issue #{{.Number}}: {{.Title}}

          Description:
          {{.Body}}

          CRITICAL: Read the issue body above carefully. Implement the changes, push the branch, and open a PR against main.
          DO NOT stop until the PR is created. The task is not complete until a PR exists.

          You have up to 100 tool-calling steps available. Use them. Do not stop early.

          If you hit errors, retry with a different approach.

          IMPORTANT: Every bash tool call MUST include a "description" parameter describing what the command does.
          Correct: bash(command: "find .", description: "Search for files")
          Wrong:   bash(command: "find .") — this will FAIL with SchemaError

          Branch: kelos-task-{{.Number}}
          Every commit message must include #{{.Number}}.
          The workspace at /workspace/repo is writable — work directly there.
        '';
        podOverrides = {
          env = [
            {
              name = "OPENAI_API_KEY";
              valueFrom.secretKeyRef = {
                name = "opencode-credentials";
                key = "OPENAI_API_KEY";
              };
            }
            {
              name = "NVIDIA_API_KEY";
              valueFrom.secretKeyRef = {
                name = "opencode-credentials";
                key = "NVIDIA_API_KEY";
              };
            }
          ];
          resources = {
            limits = {
              cpu = "1";
              memory = "1Gi";
            };
            requests = {
              cpu = "250m";
              memory = "512Mi";
            };
          };
          podSecurityContext = {
            fsGroup = 1000;
            runAsGroup = 1000;
            runAsNonRoot = true;
            runAsUser = 1000;
          };
          containerSecurityContext = {
            allowPrivilegeEscalation = false;
            capabilities.drop = ["ALL"];
            runAsNonRoot = true;
            seccompProfile.type = "RuntimeDefault";
          };
          affinity.nodeAffinity = {
            preferredDuringSchedulingIgnoredDuringExecution = [
              {
                weight = 100;
                preference.matchExpressions = [
                  {
                    key = "kubernetes.io/hostname";
                    operator = "In";
                    values = ["nexus"];
                  }
                ];
              }
              {
                weight = 50;
                preference.matchExpressions = [
                  {
                    key = "kubernetes.io/hostname";
                    operator = "In";
                    values = ["sentry"];
                  }
                ];
              }
            ];
          };
        };
        ttlSecondsAfterFinished = 900;
      };
      when.githubIssues = {
        repo = "reverb256/${r}";
        state = "open";
        labels = ["agent-ready"];
        pollInterval = "5m";
      };
    };
  };

  taskSpawners = map taskSpawnerTemplate repos;

  # AgentConfig for task execution
  agentConfig = {
    apiVersion = "kelos.dev/v1alpha1";
    kind = "AgentConfig";
    metadata = {
      name = "cluster-coder";
      namespace = "kelos-system";
      labels = {
        "app.kubernetes.io/managed-by" = "easykubenix";
        "app.kubernetes.io/part-of" = "kelos";
      };
    };
    spec = {
      agentsMD = ''
        # Kelos Agent — Task Instructions

        You were spawned by Kelos because this issue has the "agent-ready" label.

        ## Your Job
        Implement the GitHub issue that spawned you. Read the issue body, make the changes, push the branch, and open a PR against main.
        DO NOT stop until you have created a pull request. If you hit an error, try a different approach.
        The task is not complete until a PR exists at github.com/reverb256/maplespike.

        ## Before implementing
        1. Read the issue body thoroughly — it contains the exact requirements and acceptance criteria
        2. Check for ## Previous Attempt Feedback in the body — if present, fix those problems first

        ## Gateway verification
        The AI Inference Gateway is at http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1.
        The model in opencode.json is configured and valid. Use webfetch (not bash/curl) if you need to check the gateway.

        ## Critical: bash tool requires description
        Every bash call MUST include a description parameter (e.g., bash(command: "find .", description: "Find files")).
        Without it, bash calls fail with SchemaError. Retry with description if you forget.

        ## Workflow
        - The workspace at /workspace/repo is writable
        - Branch: kelos-task-NNN
        - Every commit references #NNN
        - PR body: "Closes #NNN"
      '';
      mcpServers = [
        { name = "searxng"; type = "sse"; url = "http://mcp-searxng-proxy.mcp.svc.cluster.local:8080/mcp"; }
        { name = "kb-mcp"; type = "sse"; url = "http://mcp-kb-mcp-proxy.mcp.svc.cluster.local:8080/mcp"; }
        { name = "memory"; type = "sse"; url = "http://mcp-memory-proxy.mcp.svc.cluster.local:8080/mcp"; }
        { name = "selfhosted-tools"; type = "sse"; url = "http://mcp-selfhosted-tools-proxy.mcp.svc.cluster.local:8080/mcp"; }
        { name = "sequential-thinking"; type = "sse"; url = "http://mcp-sequential-thinking-proxy.mcp.svc.cluster.local:8080/mcp"; }
        { name = "skills-mcp"; type = "sse"; url = "http://mcp-skills-mcp-proxy.mcp.svc.cluster.local:8080/mcp"; }
      ];
    };
  };

in {
  options.kubernetes.kelos = {
    enable = mkEnableOption "Kelos task orchestration";

    repo = mkOption {
      type = types.str;
      default = "maplespike";
      description = "Default repository for Kelos tasks";
    };
  };

  config = mkIf cfg.enable {
    
  # ---- Pipeline Maintenance (applied imperatively, not via Nix) ----
  # pipeline-maintenance CronJob runs every 15min on nexus.
  # It deletes failed tasks older than 15min and checks for Zephyr pods.
  # Created imperatively via kubectl apply -f /tmp/pipeline-maintenance-cronjob.yaml
  # Resources: SA/ClusterRole/CRB pipeline-operator + CronJob in kelos-system
  # NOTE: maplespike-prod ImagePullBackOff and coredns-ha-enforcer are
  # pre-existing egress issues, not pipeline-related.

  kubernetes.rawResources = workspaces ++ taskSpawners ++ [agentConfig];
  };
}

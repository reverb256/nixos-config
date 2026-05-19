# This module is managed by the Kelos controller.
# See: https://github.com/reverb256/kelos-controller

{ config, lib, pkgs, ... ,
    \"deepseek-v4-flash-free\": { \"name\": \"DeepSeek V4 Flash (Zen Free)\" },
    \"nemotron-3-super-free\": { \"name\": \"Nemotron 3 Super (Zen Free)\" },
    \"nemotron-3-super-120b-a12b\": { \"name\": \"Nemotron 3 Super 120B (NIM)\" },
    \"nemotron-3-nano-30b-a3b\": { \"name\": \"Nemotron 3 Nano 30B (NIM)\" },
    \"nemotron-3-super-120b-a12b-free\": { \"name\": \"Nemotron 3 Super Free (Kilo)\" },
    \"kimi-k2.6\": { \"name\": \"Kimi K2.6 (NIM)\" },
    \"minimax-m2.7\": { \"name\": \"MiniMax M2.7 (Go/NIM)\" },
    \"deepseek-v4-flash\": { \"name\": \"DeepSeek V4 Flash (NIM)\" },
    \"deepseek-v4-pro\": { \"name\": \"DeepSeek V4 Pro (NIM)\" },
    \"nemotron-3-nano-omni-30b-a3b-reasoning\": { \"name\": \"Nemotron 3 Nano Omni 30B (NIM)\" }}:

with lib;

let
  cfg = config.kubernetes.kelos;
  repo = cfg.repo;
  settingsJson = builtins.toJSON cfg.settings;
in
{
  options.kubernetes.kelos = {
    enable = mkEnableOption "Kelos task spawner";

    repo = mkOption {
      type = types.str;
      default = "maplespike";
      description = "Default repository name for Kelos tasks";
    };

    settings = mkOption {
      type = types.attrs;
      default = { };
      description = "Additional Kelos settings";
    };
  };

  config = mkIf cfg.enable {
    kubernetes.rawResources = [
      {
        apiVersion = "v1";
        kind = "ConfigMap";
        metadata = {
          name = "kelos-config";
          namespace = "kelos";
        };
        data = {
          "kelos-config.json" = builtins.toJSON {
            repo = "https://github.com/reverb256/${repo}.git";
            ref = "main";
          };
        };
      }

      {
        apiVersion = "batch/v1";
        kind = "CronJob";
        metadata = {
          name = "kelos-task-spawner";
          namespace = "kelos";
        };
        spec = {
          schedule = "*/5 * * * *";
          jobTemplate = {
            spec = {
              template = {
                spec = {
                  serviceAccountName = "kelos";
                  restartPolicy = "Never";
                  containers = [
                    {
                      name = "spawner";
                      image = "ghcr.io/reverb256/kelos-controller:latest";
                      env = [
                        { name = "KELOS_CONFIG", value = "/etc/kelos/kelos-config.json"; }
                        { name = "GITHUB_TOKEN", valueFrom = { secretKeyRef = { name = "github-token"; key = "token"; }; }; }
                      ];
                      volumeMounts = [
                        { name = "config"; mountPath = "/etc/kelos"; readOnly = true; }
                      ];
                    }
                  ];
                  volumes = [
                    { name = "config"; configMap = { name = "kelos-config"; }; }
                  ];
                }
              };
            };
          };
        };
      }

      {
        apiVersion = "kelos.reverb256.ca/v1";
        kind = "TaskSpawner";
        metadata = {
          name = "default";
          namespace = "kelos";
        };
        spec = {
          repo = "https://github.com/reverb256/${repo}.git";
          ref = "main";
          secretRef.name = "github-token";
          setupCommand = ["sh" "-c" "chmod -R g+rw /workspace/repo && cat > /workspace/repo/opencode.json << 'EOFOP'
{
  \"model\": \"deepseek-v4-flash-free\",
  \"enabled_providers\": [\"nvidia\"],
  \"agent\": {
    \"build\": {
      \"steps\": 100
    }
  },
  \"provider\": {
    \"nvidia\": {
      \"options\": {
        \"baseURL\": \"http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1\"
      },
      \"models\": {
        \"deepseek-v4-flash-free\": { \"name\": \"DeepSeek V4 Flash Free\", \"id\": \"deepseek-v4-flash-free\" },
        \"nemotron-3-super-free\": { \"name\": \"Nemotron 3 Super Free\", \"id\": \"nemotron-3-super-free\" },
        \"nemotron-3-nano-30b-a3b\": { \"name\": \"Nemotron 3 Nano 30B\", \"id\": \"nvidia/nemotron-3-nano-30b-a3b\" },
        \"nemotron-3-super-120b-a12b\": { \"name\": \"Nemotron 3 Super 120B\", \"id\": \"nvidia/nemotron-3-super-120b-a12b\" },
        \"nemotron-3-super-120b-a12b-free\": { \"name\": \"Nemotron 3 Super Free (Kilo)\", \"id\": \"nvidia/nemotron-3-super-120b-a12b:free\" },
        \"kimi-k2.6\": { \"name\": \"Kimi K2.6\", \"id\": \"kimi-k2.6\" },
        \"minimax-m2.7\": { \"name\": \"MiniMax M2.7\", \"id\": \"minimax-m2.7\" },
        \"deepseek-v4-flash\": { \"name\": \"DeepSeek V4 Flash\", \"id\": \"deepseek-ai/deepseek-v4-flash\" },
        \"deepseek-v4-pro\": { \"name\": \"DeepSeek V4 Pro\", \"id\": \"deepseek-ai/deepseek-v4-pro\" },
        \"nemotron-3-nano-omni-30b-a3b-reasoning\": { \"name\": \"Nemotron 3 Nano Omni 30B Reasoning\", \"id\": \"nvidia/nemotron-3-nano-omni-30b-a3b-reasoning\" }
      }
    }
  }
}
EOFOP
"];
          resources = {
            limits = { cpu = "2"; memory = "2Gi"; };
            requests = { cpu = "500m"; memory = "1Gi"; };
          };
        };
      }

      {
        apiVersion = "kelos.reverb256.ca/v1";
        kind = "AgentConfig";
        metadata = {
          name = "cluster-coder";
          namespace = "kelos";
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
            {
              name = "searxng";
              type = "sse";
              url = "http://mcp-searxng-proxy.mcp.svc.cluster.local:8080/mcp";
            }
            {
              name = "kb-mcp";
              type = "sse";
              url = "http://mcp-kb-mcp-proxy.mcp.svc.cluster.local:8080/mcp";
            }
            {
              name = "memory";
              type = "sse";
              url = "http://mcp-memory-proxy.mcp.svc.cluster.local:8080/mcp";
            }
            {
              name = "selfhosted-tools";
              type = "sse";
              url = "http://mcp-selfhosted-tools-proxy.mcp.svc.cluster.local:8080/mcp";
            }
            {
              name = "sequential-thinking";
            {
              name = "skills-mcp";
              type = "sse";
              url = "http://mcp-skills-mcp-proxy.mcp.svc.cluster.local:8080/mcp";
            }
              type = "sse";
            {
              name = "skills-mcp";
              type = "sse";
              url = "http://mcp-skills-mcp-proxy.mcp.svc.cluster.local:8080/mcp";
            }
              url = "http://mcp-sequential-thinking-proxy.mcp.svc.cluster.local:8080/mcp";
            {
              name = "skills-mcp";
              type = "sse";
              url = "http://mcp-skills-mcp-proxy.mcp.svc.cluster.local:8080/mcp";
            }
            }
            {
              name = "skills-mcp";
              type = "sse";
              url = "http://mcp-skills-mcp-proxy.mcp.svc.cluster.local:8080/mcp";
            }
          ];
            {
              name = "skills-mcp";
              type = "sse";
              url = "http://mcp-skills-mcp-proxy.mcp.svc.cluster.local:8080/mcp";
            }
        };
      }
    ];
  };
}

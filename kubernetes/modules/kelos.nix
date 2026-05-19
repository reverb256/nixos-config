# This module is managed by the Kelos controller.
# See: https://github.com/reverb256/kelos-controller

{ config, lib, pkgs, ... }:

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
  \"$schema\": \"https://opencode.ai/config.json\",
  \"model\": \"auto\",
  \"enabled_providers\": [\"nvidia\"],
  \"provider\": {
    \"nvidia\": {
      \"options\": {
        \"baseURL\": \"http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1\"
      },
      \"models\": {
        \"nemotron-3-super-120b-a12b\": { \"name\": \"Nemotron 3 Super 120B\", \"id\": \"nvidia/nemotron-3-super-120b-a12b\" },
        \"nemotron-3-nano-30b-a3b\": { \"name\": \"Nemotron 3 Nano 30B\", \"id\": \"nvidia/nemotron-3-nano-30b-a3b\" },
        \"nemotron-3-nano-omni-30b-a3b-reasoning\": { \"name\": \"Nemotron 3 Nano Omni 30B\", \"id\": \"nvidia/nemotron-3-nano-omni-30b-a3b-reasoning\" }
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
            # NixOS Cluster — Agent Guidelines (via Kelos)

            You were spawned by Kelos because this issue has the "agent-ready" label.

            ## Cluster Overview
            - 4 nodes: Zephyr (31GB), Nexus (46GB), Forge (16GB), Sentry (31GB)
            - K3s cluster with Flannel CNI
            - AI Inference Gateway at http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1

            ## Models
            - NVIDIA Nemotron 3 Super (120B) — default model for code tasks
            - NVIDIA Nemotron 3 Nano Omni (30B) — vision/reasoning tasks
            - Model selection is automatic via the AI Inference Gateway

            ## Critical Rules
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
              type = "sse";
              url = "http://mcp-sequential-thinking-proxy.mcp.svc.cluster.local:8080/mcp";
            }
          ];
        };
      }
    ];
  };
}

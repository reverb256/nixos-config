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
           setupCommand = ["sh" "-c" "chmod -R g+rw /workspace/repo && mkdir -p /workspace/repo/.opencode/commands && REPO=''${KELOS_UPSTREAM_REPO:-unknown}

# Repo-appropriate validate command
cat > /workspace/repo/.opencode/commands/validate.md << 'CMDEOF'
# Validate the project
CMDEOF

case \"$REPO\" in
  *nixos-config*)
    cat > /workspace/repo/.opencode/commands/validate.md << 'CMDEOF'
# Validate the NixOS configuration
RUN nix flake check
RUN just check
CMDEOF
    cat > /workspace/repo/.opencode/commands/deploy.md << 'CMDEOF'
# Deploy to a specific host
## Usage
Use this to apply configuration changes to a cluster node.
Make sure `nix flake check` passes first, then run:
RUN just deploy
CMDEOF
    ;;
  *maplespike*)
    cat > /workspace/repo/.opencode/commands/validate.md << 'CMDEOF'
# Validate the MapleSpike monorepo
RUN pnpm install --frozen-lockfile
RUN pnpm -r build
RUN pnpm test
CMDEOF
    cat > /workspace/repo/.opencode/commands/build.md << 'CMDEOF'
# Build all packages
RUN pnpm build
CMDEOF
    ;;
  *ai-inference-gateway*)
    cat > /workspace/repo/.opencode/commands/validate.md << 'CMDEOF'
# Validate the AI Inference Gateway
RUN pip install -e . -q
RUN pytest tests/ -x -q
CMDEOF
    ;;
  *knowledge-fabric*)
    cat > /workspace/repo/.opencode/commands/validate.md << 'CMDEOF'
# Validate the Knowledge Fabric
RUN npx tsc --noEmit
CMDEOF
    ;;
  *)
    # Generic fallback
    cat > /workspace/repo/.opencode/commands/validate.md << 'CMDEOF'
# Validate the project
## Run the appropriate validation for this repo
RUN echo \"No repo-specific validate command defined\"
CMDEOF
    ;;
esac && cat > /workspace/repo/opencode.json << 'EOFOP'
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
    ];
  };
}

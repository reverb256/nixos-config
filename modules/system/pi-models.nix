# Pi agent model registry — declarative configuration
# Writes ~/.pi/agent/models.json with model specs for local and NVIDIA providers.
# API keys are injected from sops-decrypted secrets by the systemd service.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.pi-agent;

  nvidiaModels = [
    {
      id = "deepseek-ai/deepseek-r1";
      name = "DeepSeek R1 (NVIDIA NIM)";
      reasoning = true;
      input = ["text"];
      contextWindow = 131072;
      maxTokens = 16384;
    }
    {
      id = "deepseek-ai/deepseek-v3.1";
      name = "DeepSeek V3.1 (NVIDIA NIM)";
      reasoning = true;
      input = ["text"];
      contextWindow = 131072;
      maxTokens = 16384;
    }
    {
      id = "nvidia/nemotron-3-super-120b-a12b";
      name = "Nemotron 3 Super 120B (NVIDIA NIM)";
      reasoning = true;
      input = ["text"];
      contextWindow = 1048576;
      maxTokens = 32768;
    }
    {
      id = "moonshotai/kimi-k2.5";
      name = "Kimi K2.5 (NVIDIA NIM)";
      reasoning = true;
      input = ["text" "image" "video"];
      contextWindow = 262144;
      maxTokens = 16384;
    }
    {
      id = "minimaxai/minimax-m2.5";
      name = "MiniMax M2.5 (NVIDIA NIM)";
      reasoning = true;
      input = ["text"];
      contextWindow = 204800;
      maxTokens = 16384;
    }
  ];

  aiGatewayModels = [
    {
      id = "qwen3.5-4b";
      name = "Qwen 3.5 4B (K8s Gateway)";
      reasoning = true;
      input = ["text"];
      contextWindow = 262144;
      maxTokens = 16384;
    }
    {
      id = "qwen3.5-32b";
      name = "Qwen 3.5 32B (K8s Gateway)";
      reasoning = true;
      input = ["text"];
      contextWindow = 262144;
      maxTokens = 32768;
    }
    {
      id = "deepseek-r1";
      name = "DeepSeek R1 (K8s Gateway)";
      reasoning = true;
      input = ["text"];
      contextWindow = 131072;
      maxTokens = 16384;
    }
  ];

  lmStudioModels = [
    {
      id = "qwen3.5-4b";
      name = "Qwen 3.5 4B (LM Studio)";
      reasoning = true;
      input = ["text"];
      contextWindow = 262144;
      maxTokens = 16384;
    }
  ];

  withCost = models:
    map (m:
      m
      // {
        cost = {
          input = 0;
          output = 0;
          cacheRead = 0;
          cacheWrite = 0;
        };
      })
    models;

  modelsJsonTemplate = builtins.toJSON {
    providers = {
      "nvidia-nim" = {
        baseUrl = "https://integrate.api.nvidia.com/v1";
        api = "openai-completions";
        apiKey = "@NVIDIA_API_KEY@";
        models = withCost nvidiaModels;
      };
      "ai-gateway" = {
        baseUrl = "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1";
        api = "openai-completions";
        apiKey = "k8s-gateway";
        models = withCost aiGatewayModels;
      };
      lmstudio = {
        baseUrl = "http://127.0.0.1:1234/v1";
        api = "openai-completions";
        apiKey = "lmstudio";
        models = withCost lmStudioModels;
      };
    };
  };

  user = "j_kro";
  modelsJsonDir = "/home/${user}/.pi/agent";
  modelsJsonPath = "${modelsJsonDir}/models.json";

  writeModelsJson = pkgs.writeShellScript "write-pi-models-json" ''
    set -euo pipefail

    NVIDIA_KEY_FILE="/run/secrets/nvidia-api-key"
    OUTPUT="${modelsJsonPath}"

    if [ -f "$NVIDIA_KEY_FILE" ]; then
      NVIDIA_API_KEY=$(tr -d '\n\r ' < "$NVIDIA_KEY_FILE")
    else
      echo "[pi-models] WARNING: $NVIDIA_KEY_FILE not found" >&2
      NVIDIA_API_KEY="MISSING_NVIDIA_KEY"
    fi

    mkdir -p "$(dirname "$OUTPUT")"
    sed -e "s|@NVIDIA_API_KEY@|$NVIDIA_API_KEY|g" \
      "${pkgs.writeText "models.json.template" modelsJsonTemplate}" \
      > "$OUTPUT"

    chown ${user}:${user} "$OUTPUT"
    chmod 600 "$OUTPUT"
    echo "[pi-models] Written $OUTPUT ($(wc -c < "$OUTPUT") bytes)"
  '';
in {
  options.programs.pi-agent = {
    enable = lib.mkEnableOption "pi coding agent model registry";
  };

  config = lib.mkIf cfg.enable {
    systemd.services.pi-models = {
      description = "Write pi agent models.json with API keys from sops";
      wantedBy = ["multi-user.target"];
      requires = ["sops-nix.service"];
      after = ["sops-nix.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = writeModelsJson;
        RemainAfterExit = true;
      };
    };
  };
}

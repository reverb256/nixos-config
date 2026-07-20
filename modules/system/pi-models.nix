# Pi agent model registry — declarative configuration
# Writes ~/.pi/agent/models.json with accurate model specs for all providers
#
# Providers:
#   zai        — Z.AI coding API (free tier)
#   nvidia-nim — NVIDIA NIM hosted API (free tier, integrate.api.nvidia.com)
#   ai-gateway — Local K8s inference gateway on nexus
#   lmstudio   — Local LM Studio on zephyr
#
# API keys are injected from agenix-decrypted secrets via systemd service
# that reads /run/secrets/* after agenix activation.
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.pi-agent;

  # Z.AI models — https://api.z.ai/api/coding/paas/v4
  zaiModels = [
    {
      id = "glm-5.1";
      name = "GLM-5.1 (Z.AI)";
      reasoning = true;
      input = [ "text" ];
      contextWindow = 200000;
      maxTokens = 128000;
    }
    {
      id = "glm-5";
      name = "GLM-5 (Z.AI)";
      reasoning = true;
      input = [ "text" ];
      contextWindow = 200000;
      maxTokens = 128000;
    }
    {
      id = "glm-5-turbo";
      name = "GLM-5 Turbo (Z.AI)";
      reasoning = true;
      input = [ "text" ];
      contextWindow = 200000;
      maxTokens = 128000;
    }
    {
      id = "glm-4.7";
      name = "GLM-4.7 (Z.AI)";
      reasoning = false;
      input = [ "text" ];
      contextWindow = 200000;
      maxTokens = 128000;
    }
    {
      id = "glm-4.7-flash";
      name = "GLM-4.7 Flash (Z.AI)";
      reasoning = false;
      input = [ "text" ];
      contextWindow = 131072;
      maxTokens = 16384;
    }
    {
      id = "glm-4.5-air";
      name = "GLM-4.5 Air (Z.AI)";
      reasoning = false;
      input = [ "text" ];
      contextWindow = 131100;
      maxTokens = 98304;
    }
  ];

  # NVIDIA NIM hosted models — https://integrate.api.nvidia.com/v1
  # All free tier. No Llama models.
  nvidiaModels = [
    {
      id = "deepseek-ai/deepseek-r1";
      name = "DeepSeek R1 (NVIDIA NIM)";
      reasoning = true;
      input = [ "text" ];
      contextWindow = 131072;
      maxTokens = 16384;
    }
    {
      id = "deepseek-ai/deepseek-v3.1";
      name = "DeepSeek V3.1 (NVIDIA NIM)";
      reasoning = true;
      input = [ "text" ];
      contextWindow = 131072;
      maxTokens = 16384;
    }
    {
      id = "qwen/qwen3.5-122b-a10b";
      name = "Qwen 3.5 122B (NVIDIA NIM)";
      reasoning = true;
      input = [ "text" "image" ];
      contextWindow = 262144;
      maxTokens = 32768;
    }
    {
      id = "nvidia/nemotron-3-super-120b-a12b";
      name = "Nemotron 3 Super 120B (NVIDIA NIM)";
      reasoning = true;
      input = [ "text" ];
      contextWindow = 1048576;
      maxTokens = 32768;
    }
    {
      id = "google/gemma-4-31b-it";
      name = "Gemma 4 31B IT (NVIDIA NIM)";
      reasoning = true;
      input = [ "text" "image" ];
      contextWindow = 262144;
      maxTokens = 16384;
    }
    {
      id = "moonshotai/kimi-k2.5";
      name = "Kimi K2.5 (NVIDIA NIM)";
      reasoning = true;
      input = [ "text" "image" "video" ];
      contextWindow = 262144;
      maxTokens = 16384;
    }
    {
      id = "moonshotai/kimi-k2-thinking";
      name = "Kimi K2 Thinking (NVIDIA NIM)";
      reasoning = true;
      input = [ "text" ];
      contextWindow = 262144;
      maxTokens = 16384;
    }
    {
      id = "minimaxai/minimax-m2.5";
      name = "MiniMax M2.5 (NVIDIA NIM)";
      reasoning = true;
      input = [ "text" ];
      contextWindow = 204800;
      maxTokens = 16384;
    }
  ];

  # Local K8s inference gateway — runs on nexus
  aiGatewayModels = [
    {
      id = "qwen3.5-4b";
      name = "Qwen 3.5 4B (K8s Gateway)";
      reasoning = true;
      input = [ "text" ];
      contextWindow = 262144;
      maxTokens = 16384;
    }
    {
      id = "qwen3.5-32b";
      name = "Qwen 3.5 32B (K8s Gateway)";
      reasoning = true;
      input = [ "text" ];
      contextWindow = 262144;
      maxTokens = 32768;
    }
    {
      id = "deepseek-r1";
      name = "DeepSeek R1 (K8s Gateway)";
      reasoning = true;
      input = [ "text" ];
      contextWindow = 131072;
      maxTokens = 16384;
    }
  ];

  # Local LM Studio — runs on zephyr
  lmStudioModels = [
    {
      id = "qwen3.5-4b";
      name = "Qwen 3.5 4B (LM Studio)";
      reasoning = true;
      input = [ "text" ];
      contextWindow = 262144;
      maxTokens = 16384;
    }
  ];

  # Add zero-cost to each model
  withCost = models: map (m: m // { cost = { input = 0; output = 0; cacheRead = 0; cacheWrite = 0; }; }) models;

  # JSON with placeholder tokens for API keys
  modelsJsonTemplate = builtins.toJSON {
    providers = {
      zai = {
        baseUrl = "https://api.z.ai/api/coding/paas/v4";
        api = "openai-completions";
        apiKey = "@ZAI_API_KEY@";
        models = withCost zaiModels;
      };
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

  # User to own the models.json file
  user = "j_kro";
  modelsJsonDir = "/home/${user}/.pi/agent";
  modelsJsonPath = "${modelsJsonDir}/models.json";

  # Script that reads decrypted secrets and writes final models.json
  writeModelsJson = pkgs.writeShellScript "write-pi-models-json" ''
    set -euo pipefail

    ZAI_KEY_FILE="/run/secrets/zai-api-key"
    NVIDIA_KEY_FILE="/run/secrets/nvidia-api-key"
    OUTPUT="${modelsJsonPath}"

    # Read API keys (strip trailing whitespace/newlines)
    if [ -f "$ZAI_KEY_FILE" ]; then
      ZAI_API_KEY=$(tr -d '\n\r ' < "$ZAI_KEY_FILE")
    else
      echo "[pi-models] WARNING: $ZAI_KEY_FILE not found" >&2
      ZAI_API_KEY="MISSING_ZAI_KEY"
    fi

    if [ -f "$NVIDIA_KEY_FILE" ]; then
      NVIDIA_API_KEY=$(tr -d '\n\r ' < "$NVIDIA_KEY_FILE")
    else
      echo "[pi-models] WARNING: $NVIDIA_KEY_FILE not found" >&2
      NVIDIA_API_KEY="MISSING_NVIDIA_KEY"
    fi

    # Ensure output directory exists
    mkdir -p "$(dirname "$OUTPUT")"

    # Substitute placeholders with actual keys
    sed -e "s|@ZAI_API_KEY@|$ZAI_API_KEY|g" \
        -e "s|@NVIDIA_API_KEY@|$NVIDIA_API_KEY|g" \
        "${pkgs.writeText "models.json.template" modelsJsonTemplate}" \
        > "$OUTPUT"

    chown ${user}:${user} "$OUTPUT"
    chmod 600 "$OUTPUT"
    echo "[pi-models] Written $OUTPUT ($(wc -c < "$OUTPUT") bytes)"
  '';
in
{
  options.programs.pi-agent = {
    enable = lib.mkEnableOption "pi coding agent model registry";
  };

  config = lib.mkIf cfg.enable {
    # One-shot systemd service that runs after agenix to inject secrets
    # into the models.json template
    systemd.services.pi-models = {
      description = "Write pi agent models.json with API keys from agenix";
      wantedBy = [ "multi-user.target" ];
      requires = [ "agenix.service" ];
      after = [ "agenix.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = writeModelsJson;
        RemainAfterExit = true;
      };
    };
  };
}

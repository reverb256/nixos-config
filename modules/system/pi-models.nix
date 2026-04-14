{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.pi-agent;

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

  nvidiaModels = [
    {
      id = "deepseek-ai/deepseek-v3.1";
      name = "DeepSeek V3.1 (NVIDIA NIM)";
      reasoning = true;
      input = [ "text" ];
      contextWindow = 131072;
      maxTokens = 16384;
    }
    {
      id = "deepseek-ai/deepseek-v3.2";
      name = "DeepSeek V3.2 (NVIDIA NIM)";
      reasoning = true;
      input = [ "text" ];
      contextWindow = 131072;
      maxTokens = 16384;
    }
    {
      id = "qwen/qwen3-coder-480b-a35b-instruct";
      name = "Qwen3 Coder 480B (NVIDIA NIM)";
      reasoning = true;
      input = [
        "text"
        "image"
      ];
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
      id = "moonshotai/kimi-k2-instruct";
      name = "Kimi K2 (NVIDIA NIM)";
      reasoning = true;
      input = [ "text" ];
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
      id = "moonshotai/kimi-k2.5";
      name = "Kimi K2.5 (NVIDIA NIM)";
      reasoning = true;
      input = [
        "text"
        "image"
      ];
      contextWindow = 262144;
      maxTokens = 16384;
    }
    {
      id = "meta/llama-4-maverick-17b-128e-instruct";
      name = "Llama 4 Maverick (NVIDIA NIM)";
      reasoning = true;
      input = [
        "text"
        "image"
      ];
      contextWindow = 131072;
      maxTokens = 16384;
    }
    {
      id = "bytedance/seed-oss-36b-instruct";
      name = "Seed OSS 36B (NVIDIA NIM)";
      reasoning = false;
      input = [ "text" ];
      contextWindow = 131072;
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
    {
      id = "mistralai/mistral-large-3-675b-instruct-2512";
      name = "Mistral Large 3 675B (NVIDIA NIM)";
      reasoning = true;
      input = [ "text" ];
      contextWindow = 131072;
      maxTokens = 16384;
    }
  ];

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

  llamaCppModels = [
    {
      id = "gemma-4-e4b-it";
      name = "Gemma 4 E4B IT (llama.cpp local)";
      reasoning = false;
      input = [
        "text"
        "image"
      ];
      contextWindow = 131072;
      maxTokens = 8192;
    }
  ];

  withCost =
    models:
    map (
      m:
      m
      // {
        cost = {
          input = 0;
          output = 0;
          cacheRead = 0;
          cacheWrite = 0;
        };
      }
    ) models;

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
      "llama-cpp" = {
        baseUrl = "http://127.0.0.1:1235/v1";
        api = "openai-completions";
        apiKey = "unused";
        models = withCost llamaCppModels;
      };
    };
  };

  user = "j_kro";
  modelsJsonDir = "/home/${user}/.pi/agent";
  modelsJsonPath = "${modelsJsonDir}/models.json";

  writeModelsJson = pkgs.writeShellScript "write-pi-models-json" ''
    set -euo pipefail

    ZAI_KEY_FILE="/run/agenix/zai-api-key"
    NVIDIA_KEY_FILE="/run/agenix/nvidia-api-key"
    OUTPUT="${modelsJsonPath}"

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

    mkdir -p "$(dirname "$OUTPUT")"

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

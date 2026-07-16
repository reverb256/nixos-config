# Unified AI Model Registry — Single Source of Truth
# Last Updated: 2026-05-21
# Strategy: Local (Private) → NIM (Unlimited) → Gemma (Fast/Privacy)
#           → OpenCode Go (Daily reset 7PM) → Free routers
# This file is imported by model-sync CronJob to generate Pi/OmP configs
# and consumed by ai-coding-tools module for tool config generation.
{
  # ── Defaults ─────────────────────────────────────────────────────────
  defaults = {
    primary = "nvidia/nemotron-3-nano-30b-a3b";
    fallback = "google/gemma-2b";
    smol = "local/qwen3.5-2b-awq"; # Local, no external dependency
    slow = "local/qwen3.6-moe-35b"; # Local, best reasoning
    plan = "deepseek-ai/deepseek-v4-flash"; # NIM, rate-limited
    commit = "local/qwen3.6-moe-35b"; # Local primary
    code = "deepseek-ai/deepseek-v4-flash"; # NIM, rate-limited
    vision = "qwen/qwen3.5-397b-a17b"; # NIM, vision
  };

  # ── Models ─────────────────────────────────────────────────────────
  models = {
    # ── LOCAL MODELS (Private / Baseline) ───────────────────────────
    local-qwen-2b = {
      id = "local/qwen3.5-2b-awq";
      name = "Qwen3.5 2B AWQ";
      category = "fast";
      contextWindow = 180000;
      url = "http://10.1.1.120:8040/v1";
      provider = "local-vllm";
      gpu = "RTX 3060 Ti 8GB";
      host = "nexus";
      priority = 1;
    };
    local-qwen-4b = {
      id = "local/qwen3.5-4b";
      name = "Qwen3.5 4B Q4_K_M";
      category = "fast";
      contextWindow = 262144;
      url = "http://10.1.1.140:1235/v1";
      provider = "local-sentry";
      gpu = "Radeon RX 5600 XT 6GB (Vulkan)";
      host = "sentry";
      vision = true;
      priority = 1;
    };
    local-qwen-27b = {
      id = "local/qwen3.5-27b";
      name = "Qwen3.5 27B Q4_K_M";
      category = "reasoning";
      contextWindow = 262144;
      url = "http://10.1.1.110:1237/v1";
      provider = "local-zephyr-3090";
      gpu = "RTX 3090 24GB";
      host = "zephyr";
      priority = 1;
    };
    local-qwen-35b-moe = {
      id = "local/qwen3.6-moe-35b";
      name = "Carnice Qwen3.6 35B MoE IQ4_XS";
      category = "reasoning";
      contextWindow = 262144;
      url = "http://10.1.1.110:1237/v1";
      provider = "local-zephyr-3090";
      gpu = "RTX 3090 24GB";
      host = "zephyr";
      vision = true;
      reasoning = true;
      priority = 1;
    };

    # ── NVIDIA NIM (Primary / Unlimited) ──────────────────────────
    nemotron-3-super = {
      id = "nvidia/nemotron-3-super-120b-a12b";
      name = "Nemotron 3 Super 120B";
      category = "reasoning";
      contextWindow = 1000000;
      provider = "nvidia-nim";
      quotaMultiplier = 1;
      capabilities = ["chat" "completion" "reasoning" "tool_calling" "agentic"];
      priority = 2;
    };
    nemotron-3-nano = {
      id = "nvidia/nemotron-3-nano-30b-a3b";
      name = "Nemotron 3 Nano 30B";
      category = "fast";
      contextWindow = 1000000;
      provider = "nvidia-nim";
      quotaMultiplier = 1;
      capabilities = ["chat" "completion"];
      priority = 2;
    };
    nemotron-3-nano-omni = {
      id = "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning";
      name = "Nemotron 3 Nano Omni";
      category = "reasoning";
      contextWindow = 1000000;
      provider = "nvidia-nim";
      quotaMultiplier = 1;
      capabilities = ["chat" "completion" "vision" "audio" "reasoning"];
      priority = 2;
    };

    # ── GOOGLE GEMMA (Fast / Privacy-Conscious) ─────────────────────
    gemma-4-31b = {
      id = "google/gemma-4-31b-it";
      name = "Gemma 4 31B";
      category = "reasoning";
      contextWindow = 262144;
      provider = "google";
      capabilities = ["chat" "completion" "coding"];
      priority = 3;
    };
    gemma-4-26b = {
      id = "google/gemma-4-26b-a4b-it";
      name = "Gemma 4 26B A4B";
      category = "fast";
      contextWindow = 262144;
      provider = "google";
      capabilities = ["chat" "completion" "coding"];
      priority = 3;
    };
    gemma-3-12b = {
      id = "google/gemma-3-12b-it";
      name = "Gemma 3 12B";
      category = "fast";
      contextWindow = 131072;
      provider = "google";
      capabilities = ["chat" "completion"];
      priority = 3;
    };
    gemma-3-4b = {
      id = "google/gemma-3-4b-it";
      name = "Gemma 3 4B";
      category = "fast";
      contextWindow = 131072;
      provider = "google";
      capabilities = ["chat" "completion"];
      priority = 3;
    };
    gemma-2b = {
      id = "google/gemma-2b";
      name = "Gemma 2B";
      category = "fast";
      contextWindow = 131072;
      provider = "google";
      capabilities = ["chat" "completion"];
      priority = 3;
    };

    # ── QWEN MODELS (NIM / Gateway) ──────────────────────────────
    qwen3-5-flash = {
      id = "qwen/qwen3.5-flash-02-23";
      name = "Qwen3.5 Flash 1M context";
      category = "fast";
      contextWindow = 1000000;
      provider = "gateway";
      priority = 4;
    };

    # ── QWEN MODELS (NIM / Gateway) ──────────────────────────────
    qwen3-5-397b = {
      id = "qwen/qwen3.5-397b-a17b";
      name = "Qwen3.5 397B A17B";
      category = "reasoning";
      contextWindow = 1000000;
      provider = "gateway";
      vision = true;
      priority = 4;
    };
    qwen3-5-122b = {
      id = "qwen/qwen3.5-122b-a10b";
      name = "Qwen3.5 122B A10B";
      category = "reasoning";
      contextWindow = 131072;
      provider = "gateway";
      priority = 4;
    };
    qwen3-next-80b = {
      id = "qwen/qwen3-next-80b-a3b-instruct";
      name = "Qwen3 Next 80B";
      category = "reasoning";
      contextWindow = 131072;
      provider = "gateway";
      priority = 4;
    };

    # ── DEEPSEEK MODELS ─────────────────────────────────────────────
    deepseek-v4-pro = {
      id = "deepseek-ai/deepseek-v4-pro";
      name = "DeepSeek V4 Pro 1M context";
      category = "reasoning";
      contextWindow = 1000000;
      provider = "gateway";
      priority = 4;
    };
    deepseek-v4-flash = {
      id = "deepseek-ai/deepseek-v4-flash";
      name = "DeepSeek V4 Flash (NIM)";
      category = "code";
      contextWindow = 1000000;
      provider = "gateway";
      priority = 4;
    };
    deepseek-v4-flash-opencode = {
      id = "opencode/deepseek-v4-flash";
      name = "DeepSeek V4 Flash (OpenCode Go, 5h+weekly cap)";
      category = "code";
      contextWindow = 1000000;
      provider = "opencode-go";
      quotaMultiplier = 0;
      priority = 5;
    };
    deepseek-v4-flash-zen = {
      id = "deepseek-v4-flash";
      name = "DeepSeek V4 Flash — OpenCode Zen Free";
      category = "code";
      contextWindow = 1048576;
      provider = "opencode-zen";
      priority = 5;
    };

    # ── xAI GROK (Direct OAuth via ~/.local/share/opencode/auth.json) ─────
    "grok-4.20-reasoning" = {
      id = "grok-4.20-0309-reasoning";
      name = "Grok-4.20-0309 Reasoning";
      category = "reasoning";
      contextWindow = 2000000;
      maxOutputTokens = 2000000;
      provider = "xai";
      priority = 1;
    };

    "grok-4.20-non-reasoning" = {
      id = "grok-4.20-0309-non-reasoning";
      name = "Grok-4.20-0309 Non-Reasoning";
      category = "fast";
      contextWindow = 2000000;
      maxOutputTokens = 2000000;
      provider = "xai";
      priority = 2;
    };

    "grok-4.20-multi-agent" = {
      id = "grok-4.20-multi-agent-0309";
      name = "Grok-4.20 Multi-Agent 0309";
      category = "reasoning";
      contextWindow = 2000000;
      maxOutputTokens = 2000000;
      provider = "xai";
      priority = 3;
    };

    "grok-4.3" = {
      id = "grok-4.3";
      name = "Grok-4.3";
      category = "reasoning";
      contextWindow = 1000000;
      maxOutputTokens = 1000000;
      provider = "xai";
      priority = 4;
    };

    "grok-build-0.1" = {
      id = "grok-build-0.1";
      name = "Grok Build 0.1";
      category = "code";
      contextWindow = 2000000;
      maxOutputTokens = 2000000;
      provider = "xai";
      priority = 5;
    };

    grok-imagine-image = {
      id = "grok-imagine-image";
      name = "Grok Imagine Image";
      category = "image";
      contextWindow = 0;
      maxOutputTokens = 0;
      provider = "xai";
      priority = 10;
    };

    grok-imagine-image-quality = {
      id = "grok-imagine-image-quality";
      name = "Grok Imagine Image Quality";
      category = "image";
      contextWindow = 0;
      maxOutputTokens = 0;
      provider = "xai";
      priority = 10;
    };

    grok-imagine-video = {
      id = "grok-imagine-video";
      name = "Grok Imagine Video";
      category = "video";
      contextWindow = 0;
      maxOutputTokens = 0;
      provider = "xai";
      priority = 10;
    };
  };

  # ── Backend Providers ──────────────────────────────────────────────
  providers = {
    gateway = {
      type = "openai-compatible";
      url = "http://10.1.1.110:8080/v1";
      host = "zephyr";
      modelAlias = true;
    };
    local-vllm = {
      type = "vllm";
      url = "http://10.1.1.120:8040/v1";
      host = "nexus";
      gpu = "RTX 3060 Ti 8GB";
    };
    local-zephyr-3090 = {
      type = "llama-cpp";
      url = "http://10.1.1.110:1237/v1";
      host = "zephyr";
      gpu = "RTX 3090 24GB";
    };
    local-sentry = {
      type = "llama-cpp";
      url = "http://10.1.1.140:1235/v1";
      host = "sentry";
      gpu = "Radeon RX 5600 XT 6GB (Vulkan)";
    };
    nvidia-nim = {
      type = "nvidia-nim";
      url = "https://integrate.api.nvidia.com/v1";
      host = "external";
    };
    opencode-go = {
      type = "openai-compatible";
      url = "https://api.opencode.go/v1";
      host = "external";
    };
    opencode-zen = {
      type = "openai-compatible";
      url = "https://api.opencode.go/v1";
      host = "external";
    };
    google = {
      type = "openai-compatible";
      url = "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1";
      host = "cluster";
    };
    xai = {
      type = "openai-compatible";
      url = "https://api.x.ai/v1";
      host = "external";
    };
  };

  # ── Host IP Map ────────────────────────────────────────────────────
  hosts = {
    zephyr = "10.1.1.110";
    nexus = "10.1.1.120";
    sentry = "10.1.1.140";
    forge = "10.1.1.130";
  };
}

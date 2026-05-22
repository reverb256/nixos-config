# Unified AI Model Registry — Single Source of Truth
# Last Updated: 2026-05-21
# Strategy: Local (Private) → NIM (Unlimited) → Gemma (Fast/Privacy)
#           → GLM (Quota-limited) → OpenCode Go (Daily reset 7PM) → Free routers
# This file is imported by model-sync CronJob to generate Pi/OmP configs
# and consumed by ai-coding-tools module for tool config generation.

{
  # ── Defaults ─────────────────────────────────────────────────────────
  defaults = {
    primary = "nvidia/nemorton-3-nano-30b-a3b";
    fallback = "google/gemma-2b";
    default = "glm-4.7"; # 1x quota, cheapest primary
    smol = "local/qwen3.5-2b-awq"; # Local, no external dependency
    slow = "local/qwen3.6-moe-35b"; # Local, best reasoning
    plan = "nvidia/deepseek-v4-flash"; # NIM, 1M context
    commit = "local/qwen3.6-moe-35b"; # Local primary
    code = "nvidia/deepseek-v4-flash"; # NIM, 1M context
    vision = "nvidia/qwen3.5-397b-a17b"; # NIM, 262K
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

    # ── STUB: 27B Dense (Future Use, not yet downloaded) ───────
    # Commented out until model is available. Same endpoint as 35B MoE.
    # local-qwen-27b-dense = {
    #   id = "local/qwen3.5-27b-dense";
    #   name = "Qwen3.5 27B Dense (STUB - not downloaded)";
    #   category = "reasoning";
    #   contextWindow = 262144;
    #   url = "http://10.1.1.110:1237/v1";
    #   provider = "local-zephyr-3090";
    #   gpu = "RTX 3090 24GB";
    #   host = "zephyr";
    #   priority = 1;  # Comment out when enabling
    # };

    # ── NVIDIA NIM (Primary / Unlimited) ──────────────────────────
    nemotron-3-super = {
      id = "nvidia/nemotron-3-super-120b-a12b";
      name = "Nemotron 3 Super 120B";
      category = "reasoning";
      contextWindow = 262144;
      provider = "nvidia-nim";
      quotaMultiplier = 1;
      capabilities = ["chat" "completion" "reasoning" "tool_calling" "agentic"];
      priority = 2;
    };
    nemotron-3-nano = {
      id = "nvidia/nemotron-3-nano-30b-a3b";
      name = "Nemotron 3 Nano 30B";
      category = "fast";
      contextWindow = 262144;
      provider = "nvidia-nim";
      quotaMultiplier = 1;
      capabilities = ["chat" "completion"];
      priority = 2;
    };
    nemotron-3-nano-omni = {
      id = "nvidia/nemorton-3-nano-omni-30b-a3b-reasoning";
      name = "Nemotron 3 Nano Omni";
      category = "reasoning";
      contextWindow = 256000;
      provider = "nvidia-nim";
      quotaMultiplier = 1;
      capabilities = ["chat" "completion" "vision" "audio" "reasoning"];
      priority = 2;
    };
    glm-5-1-nim = {
      id = "nvidia/glm-5.1";
      name = "GLM-5.1 (NIM, 131K)";
      category = "primary";
      contextWindow = 131072;
      provider = "nvidia-nim";
      quotaMultiplier = 2;
      priority = 2;
    };
    nemorton-3-super-zen-free = {
      id = "nemotron-3-super-free";
      name = "Nemorton 3 Super 120B (OpenCode Zen Free, 1M)";
      category = "reasoning";
      contextWindow = 1000000;
      provider = "opencode-zen-free";
      quotaMultiplier = 0;
      capabilities = ["chat" "completion" "reasoning" "agentic"];
      priority = 6;
    };
    nemorton-3-nano-omni-zen-free = {
      id = "nemorton-3-nano-omni-free";
      name = "Nemorton 3 Nano Omni (OpenCode Zen Free, 256K)";
      category = "reasoning";
      contextWindow = 256000;
      provider = "opencode-zen-free";
      quotaMultiplier = 0;
      capabilities = ["chat" "completion" "vision" "audio" "reasoning"];
      priority = 6;
    };
 
    # ── GOOGLE GEMMA (Fast / Privacy-Conscious) ─────────────────────
    gemma-4-31b = {
      id = "google/gemma-4-31b-it";
      name = "Gemma 4 31B";
      category = "reasoning";
      contextWindow = 131072;
      provider = "google";
      capabilities = ["chat" "completion" "coding"];
      priority = 3;
    };
    gemma-4-26b = {
      id = "google/gemma-4-26b-a4b-it";
      name = "Gemma 4 26B A4B";
      category = "fast";
      contextWindow = 131072;
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

    # ── GLM MODELS (Z.AI / Quota-Managed) ───────────────────────────
    glm-5-1 = {
      id = "glm-5.1";
      name = "GLM-5.1 744B MoE orchestrator";
      category = "primary";
      contextWindow = 128000;
      provider = "gateway";
      quotaMultiplier = 2;
      priority = 4;
    };
    glm-5-turbo = {
      id = "glm-5-turbo";
      name = "GLM-5 Turbo fast agentic";
      category = "primary";
      contextWindow = 128000;
      provider = "gateway";
      quotaMultiplier = 2;
      priority = 4;
    };
    glm-4-7 = {
      id = "glm-4.7";
      name = "GLM-4.7 358B MoE";
      category = "primary";
      contextWindow = 128000;
      provider = "gateway";
      quotaMultiplier = 1;
      priority = 4;
    };
    glm-4-7-flash = {
      id = "glm-4.7-flash";
      name = "GLM-4.7 Flash 30B vision";
      category = "fast";
      contextWindow = 128000;
      provider = "gateway";
      quotaMultiplier = 1;
      capabilities = ["chat" "completion" "vision" "fast"];
      priority = 4;
    };
    glm-4-5-air = {
      id = "glm-4.5-air";
      name = "GLM-4.5 Air ultra-fast";
      category = "fast";
      contextWindow = 128000;
      provider = "gateway";
      quotaMultiplier = 1;
      priority = 4;
    };
    qwen3-5-flash = {
      id = "qwen/qwen3.5-flash-02-23";
      name = "Qwen3.5 Flash 1M context";
      category = "fast";
      contextWindow = 1000000;
      provider = "gateway";
      priority = 4;
    };

    # ── QWEN MODELS (NIM) ──────────────────────────────────────────
    qwen3-5-397b-nim = {
      id = "nvidia/qwen3.5-397b-a17b";
      name = "Qwen3.5 397B A17B (NIM, 262K)";
      category = "reasoning";
      contextWindow = 262144;
      provider = "nvidia-nim";
      quotaMultiplier = 1;
      vision = true;
      priority = 2;
    };
    qwen3-5-122b-nim = {
      id = "nvidia/qwen3.5-122b-a10b";
      name = "Qwen3.5 122B A10B (NIM, 262K→1M)";
      category = "reasoning";
      contextWindow = 262144;
      provider = "nvidia-nim";
      quotaMultiplier = 1;
      priority = 2;
    };
    qwen3-next-80b-nim = {
      id = "nvidia/qwen3-next-80b-a3b-instruct";
      name = "Qwen3 Next 80B (NIM, 262K→1M)";
      category = "reasoning";
      contextWindow = 262144;
      provider = "nvidia-nim";
      quotaMultiplier = 1;
      priority = 2;
    };

    # ── DEEPSEEK MODELS (NIM) ───────────────────────────────────────
    deepseek-v4-pro-nim = {
      id = "nvidia/deepseek-v4-pro";
      name = "DeepSeek V4 Pro (NIM, 1M)";
      category = "reasoning";
      contextWindow = 1000000;
      provider = "nvidia-nim";
      quotaMultiplier = 1;
      priority = 2;
    };
    deepseek-v4-flash-nim = {
      id = "nvidia/deepseek-v4-flash";
      name = "DeepSeek V4 Flash (NIM, 1M)";
      category = "code";
      contextWindow = 1000000;
      provider = "nvidia-nim";
      quotaMultiplier = 1;
      priority = 2;
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

    # ── EXTERNAL PROVIDERS ───────────────────────────────────────────
    mistral-large-3 = {
      id = "mistralai/mistral-large-3-675b-instruct-2512";
      name = "Mistral Large 3 675B";
      category = "reasoning";
      contextWindow = 128000;
      provider = "gateway";
      priority = 4;
    };

    # ── FREE TIER ROUTERS ──────────────────────────────────────────
    kilo-auto = {
      id = "kilo-auto/free";
      name = "Kilo auto free router";
      category = "free";
      provider = "gateway";
      quotaMultiplier = 0;
      priority = 6;
    };
    openrouter-free = {
      id = "openrouter/free";
      name = "OpenRouter free router";
      category = "free";
      provider = "gateway";
      quotaMultiplier = 0;
      priority = 6;
    };
  };

  # ── Model Roles ─────────────────────────────────────────────────────
  # Priority: local > GLM-4.7 (1x) > NIM (rate-limited) > GLM-5 (2x/3x) > free
  roles = {
    default = "glm-4.7";
    smol = "local/qwen3.5-2b-awq";
    slow = "local/qwen3.6-moe-35b";
    plan = "nvidia/deepseek-v4-flash";
    commit = "local/qwen3.6-moe-35b";
    code = "nvidia/deepseek-v4-flash";
    vision = "nvidia/qwen3.5-397b-a17b";
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
    opencode-zen-free = {
      type = "openai-compatible";
      url = "https://opencode.ai/zen/v1/chat/completions";
      host = "external";
    };
    google = {
      type = "openai-compatible";
      url = "http://ai-inference-gateway.ai-inference.svc.cluster.local:8080/v1";
      host = "cluster";
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

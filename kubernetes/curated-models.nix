# Curated Model Registry
# Single source of truth for all AI coding tool configs
# This file is imported by model-sync CronJob to generate Pi/OmP configs

{
  models = {
    # ── PRIMARY (Z.AI coding plan) ─────────────────────────────────────
    glm-5-1 = {
      id = "glm-5.1";
      name = "GLM-5.1 744B MoE orchestrator";
      category = "primary";
      quotaMultiplier = 2; # 2x normally, 3x peak hours (1400-1800 UTC+8)
      provider = "gateway";
    };
    glm-5-turbo = {
      id = "glm-5-turbo";
      name = "GLM-5 Turbo fast agentic";
      category = "primary";
      quotaMultiplier = 2; # 2x normally, 3x peak hours
      provider = "gateway";
    };
    glm-4-7 = {
      id = "glm-4.7";
      name = "GLM-4.7 358B MoE";
      category = "primary";
      quotaMultiplier = 1; # 1x usage
      provider = "gateway";
    };

    # ── FAST (local + Z.AI) ───────────────────────────────────────────────
    glm-4-5-air = {
      id = "glm-4.5-air";
      name = "GLM-4.5 Air ultra-fast";
      category = "fast";
      quotaMultiplier = 1;
      provider = "gateway";
    };
    qwen3-5-2b-awq = {
      id = "local/qwen3.5-2b-awq";
      name = "Qwen3.5 2B AWQ";
      category = "fast";
      contextWindow = 180000;
      url = "http://10.1.1.120:8040/v1"; # Nexus vLLM
      provider = "local-vllm";
    };
    qwen3-5-4b = {
      id = "local/qwen3.5-4b";
      name = "Qwen3.5 4B Q4";
      category = "fast";
      contextWindow = 262144;
      url = "http://10.1.1.140:1235/v1"; # Sentry llama.cpp
      provider = "local-sentry";
      vision = true;
    };
    qwen3-5-flash = {
      id = "qwen/qwen3.5-flash-02-23";
      name = "Qwen3.5 Flash 1M context";
      category = "fast";
      contextWindow = 1000000;
      provider = "gateway";
    };

    # ── REASONING (local + NIM) ────────────────────────────────────────────
    qwen3-6-moe-35b = {
      id = "local/qwen3.6-moe-35b";
      name = "Carnice Qwen3.6 35B MoE IQ4_XS";
      category = "reasoning";
      contextWindow = 262144;
      url = "http://10.1.1.110:1237/v1"; # Zephyr llama.cpp
      provider = "local-zephyr-3090";
      vision = true;
      reasoning = true;
    };
    qwen3-5-397b-a17b = {
      id = "qwen/qwen3.5-397b-a17b";
      name = "Qwen3.5 397B A17B";
      category = "reasoning";
      contextWindow = 1000000;
      provider = "gateway";
      vision = true;
    };
    qwen3-5-122b-a10b = {
      id = "qwen/qwen3.5-122b-a10b";
      name = "Qwen3.5 122B A10B";
      category = "reasoning";
      provider = "gateway";
    };
    qwen3-next-80b = {
      id = "qwen/qwen3-next-80b-a3b-instruct";
      name = "Qwen3 Next 80B";
      category = "reasoning";
      provider = "gateway";
    };
    mistral-large-3 = {
      id = "mistralai/mistral-large-3-675b-instruct-2512";
      name = "Mistral Large 3 675B";
      category = "reasoning";
      provider = "gateway";
    };
    deepseek-v4-pro = {
      id = "deepseek-ai/deepseek-v4-pro";
      name = "DeepSeek V4 Pro 1M ctx";
      category = "reasoning";
      contextWindow = 1000000;
      provider = "gateway";
    };

    # ── CODE (NIM + opencode-go fallback) ─────────────────────────────────────
    deepseek-v4-flash = {
      id = "deepseek-ai/deepseek-v4-flash";
      name = "DeepSeek V4 Flash (NIM)";
      category = "code";
      contextWindow = 1000000;
      provider = "gateway";
    };
    deepseek-v4-flash-opencode = {
      id = "opencode/deepseek-v4-flash";
      name = "DeepSeek V4 Flash (OpenCode Go, 5h+weekly cap)";
      category = "code";
      contextWindow = 1000000;
      provider = "opencode-go";
    };

    # ── FREE TIER ─────────────────────────────────────────────────────────
    kilo-auto = {
      id = "kilo-auto/free";
      name = "Kilo auto free router";
      category = "free";
      provider = "gateway";
    };
    openrouter-free = {
      id = "openrouter/free";
      name = "OpenRouter free router";
      category = "free";
      provider = "gateway";
    };
  };

  # Model roles for different use cases
  # Priority: local > GLM-4.7 (1x) > NIM (rate-limited) > GLM-5 (2x/3x) > free
  roles = {
    default = "glm-4.7";  # 1x quota, always cheapest
    smol = "local/qwen3.5-2b-awq";  # Local, no external dependency
    slow = "local/qwen3.6-moe-35b";  # Local, best reasoning
    plan = "deepseek-ai/deepseek-v4-flash";  # NIM, rate-limited
    commit = "local/qwen3.6-moe-35b";  # Local primary
    code = "deepseek-ai/deepseek-v4-flash";  # NIM, rate-limited
    vision = "qwen/qwen3.5-397b-a17b";  # NIM, vision
  };

  # Provider configuration
  providers = {
    gateway.url = "http://10.1.1.110:8080/v1"; # TODO: use cluster constants
    local-vllm.url = "http://10.1.1.120:8040/v1";
    local-zephyr-3090.url = "http://10.1.1.110:1237/v1";
    local-sentry.url = "http://10.1.1.140:1235/v1";
    opencode-go.url = "http://10.1.1.110:8080/v1";
  };

  # For cluster constant integration (when available)
  hosts = {
    zephyr = "10.1.1.110";
    nexus = "10.1.1.120";
    sentry = "10.1.1.140";
  };
}
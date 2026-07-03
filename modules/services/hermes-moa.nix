{
  default_preset = "turbo";
  presets = {
    turbo = {
      reference_models = [
        { provider = "nvidia"; model = "stepfun-ai/step-3.7-flash"; }
        { provider = "nvidia"; model = "deepseek-ai/deepseek-v4-flash"; }
      ];
      aggregator = { provider = "nvidia"; model = "qwen/qwen3.5-122b-a10b"; };
      reference_temperature = 0.5;
      aggregator_temperature = 0.4;
      reference_max_tokens = 600;
      max_tokens = 16384;
      enabled = true;
    };
    balanced = {
      reference_models = [
        { provider = "nvidia"; model = "moonshotai/kimi-k2.6"; }
        { provider = "nvidia"; model = "deepseek-ai/deepseek-v4-flash"; }
      ];
      aggregator = { provider = "nvidia"; model = "qwen/qwen3.5-122b-a10b"; };
      reference_temperature = 0.5;
      aggregator_temperature = 0.4;
      reference_max_tokens = 600;
      max_tokens = 16384;
      enabled = true;
    };
    quality = {
      reference_models = [
        { provider = "nvidia"; model = "minimaxai/minimax-m2.7"; }
        { provider = "nvidia"; model = "nvidia/nemotron-3-super-120b-a12b"; }
      ];
      aggregator = { provider = "nvidia"; model = "qwen/qwen3.5-397b-a17b"; };
      reference_temperature = 0.6;
      aggregator_temperature = 0.4;
      reference_max_tokens = 600;
      max_tokens = 16384;
      enabled = true;
    };
    heavy-design = {
      reference_models = [
        { provider = "nvidia"; model = "nvidia/nemotron-3-ultra-550b-a55b"; }
        { provider = "nvidia"; model = "deepseek-ai/deepseek-v4-pro"; }
      ];
      aggregator = { provider = "nvidia"; model = "qwen/qwen3.5-397b-a17b"; };
      reference_temperature = 0.7;
      aggregator_temperature = 0.35;
      reference_max_tokens = 600;
      max_tokens = 32768;
      enabled = true;
    };
    mining-thermal = {
      reference_models = [
        { provider = "llama-cpp-sentry"; model = "Qwen3.5-4B-Q4_K_M.gguf"; }
        { provider = "nvidia"; model = "stepfun-ai/step-3.7-flash"; }
      ];
      aggregator = { provider = "nvidia"; model = "qwen/qwen3.5-122b-a10b"; };
      reference_temperature = 0.6;
      aggregator_temperature = 0.4;
      reference_max_tokens = 600;
      max_tokens = 16384;
      enabled = true;
    };
    coding = {
      reference_models = [
        { provider = "nvidia"; model = "stepfun-ai/step-3.7-flash"; }
        { provider = "nvidia"; model = "moonshotai/kimi-k2.6"; }
      ];
      aggregator = { provider = "nvidia"; model = "qwen/qwen3.5-122b-a10b"; };
      reference_temperature = 0.4;
      aggregator_temperature = 0.3;
      reference_max_tokens = 600;
      max_tokens = 16384;
      enabled = true;
    };
    research = {
      reference_models = [
        { provider = "nvidia"; model = "nvidia/nemotron-3-ultra-550b-a55b"; }
        { provider = "nvidia"; model = "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning"; }
      ];
      aggregator = { provider = "nvidia"; model = "qwen/qwen3.5-397b-a17b"; };
      reference_temperature = 0.7;
      aggregator_temperature = 0.4;
      reference_max_tokens = 600;
      max_tokens = 32768;
      enabled = true;
    };
  };
}
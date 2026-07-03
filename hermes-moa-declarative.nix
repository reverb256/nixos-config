{ config, pkgs, lib, ... }:

{
  services.hermes-cli = {
    enable = true;
    user = "j_kro";
    managedConfig = true;

    managedProviders = {
      opencode-zen = {
        api_key_env = "OPENCODE_API_KEY";
        base_url = "https://opencode.ai/zen/v1";
        discover_models = true;
        model = "nemotron-3-ultra-free";
      };
      opencode-go = {
        api_key_env = "OPENCODE_GO_API_KEY";
        base_url = "https://opencode.ai/zen/go/v1";
        discover_models = true;
      };
      zai = {
        api_key_env = "ZAI_API_KEY";
        base_url = "https://api.z.ai/api/coding/paas/v4";
        discover_models = true;
        model = "glm-4.7";
      };
      nvidia = {
        api_key_env = "NVIDIA_API_KEY";
        base_url = "https://integrate.api.nvidia.com/v1";
        discover_models = true;
      };
      llama-cpp-sentry = {
        base_url = "http://llama-server-sentry.ai-inference.svc.cluster.local:1235/v1";
        api_key = "unused";
        model = "Qwen3.5-4B-Q4_K_M.gguf";
      };
    };

    managedFallbackProviders = [
      "opencode-zen"
      "opencode-go"
      "zai"
      "nvidia"
    ];

    managedMoA = {
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
    };
  };
}

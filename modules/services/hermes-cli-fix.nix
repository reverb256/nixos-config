# This file replaces the heredoc section in hermes-cli.nix lines 206-259
# Add this as a let binding before the hermesCli definition:

configYamlContent = ''
  # Managed by NixOS - hermes-cli module
  # LOCAL MODELS AS DEFAULT - Cloud fallback available
  model:
    provider: vllm-3060ti
    default: qwen3.5-2b-awq
  
  providers:
    vllm-3060ti:
      base_url: http://10.1.1.110:8040/v1
      model: qwen3.5-2b-awq
    llama-zephyr-3090:
      base_url: http://10.1.1.110:1237/v1
      model: Carnice-Qwen3.6-MoE-35B-A3B.IQ4_XS.gguf
    llama-sentry:
      base_url: http://10.1.1.140:1235/v1
      model: Qwen3.5-4B-Q4_K_M.gguf
    zai:
      base_url: https://api.z.ai/api/coding/paas/v4
      api_key_env: ZAI_API_KEY
    glm-flash:
      base_url: http://10.15.67.242:8080/v1
      model: glm-4.5-flash
      api_key_env: ZAI_API_KEY
  
  fallback_providers:
    - vllm-3060ti
    - llama-zephyr-3090
    - llama-sentry
    - glm-flash
    - zai
  
  terminal:
    backend: local
    timeout: 180
  
  toolsets:
    - all
  
  memory:
    memory_enabled: true
    user_profile_enabled: true
  
  compression:
    enabled: true
    threshold: 0.9
'';

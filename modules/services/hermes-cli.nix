# Hermes Agent CLI module
#
# Installs the hermes CLI tool for interactive use on any host.
# Each host gets its own ~/.hermes/ state directory with unified config
# pointing to the Z.AI provider (same model, tools, personality everywhere).
#
# On hosts where services.hermes-agent is enabled, this module only installs
# the package and fish completions - the hermes-agent module handles HERMES_HOME
# and state directory setup.
#
# Usage:
#   services.hermes-cli.enable = true;
#   services.hermes-cli.apiKeyFile = config.age.secrets.zai-api-key.path;

{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.services.hermes-cli;
  hermesAgentCfg = config.services.hermes-agent or {};
  hermesPkg = inputs.hermes-agent.packages.${pkgs.system}.default;
  # If hermes-agent is enabled, use its state dir. Otherwise, use user home.
  useAgentStateDir = hermesAgentCfg.enable or false;
in
{
  options.services.hermes-cli = {
    enable = lib.mkEnableOption "Hermes Agent CLI for interactive use";

    user = lib.mkOption {
      type = lib.types.str;
      default = "j_kro";
      description = "User who will run hermes CLI";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "glm-5.1";
      description = "Default model to use";
    };

    personality = lib.mkOption {
      type = lib.types.lines;
      default = ''
        You are Hermes Agent, an intelligent AI assistant created by Nous Research.
        You are helpful, knowledgeable, and direct. You assist users with a wide range
        of tasks including answering questions, writing and editing code, analyzing
        information, and creative work.
      '';
      description = "Agent personality (written to SOUL.md)";
    };

    apiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to agenix secret file containing ZAI_API_KEY";
      example = "config.age.secrets.zai-api-key.path";
    };

    nvidiaApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to agenix secret file containing NVIDIA_API_KEY";
      example = "config.age.secrets.nvidia-api-key.path";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install hermes package system-wide
    environment.systemPackages = [ hermesPkg ];

    # Only set HERMES_HOME if hermes-agent is NOT managing it
    # The hermes-agent module sets addToSystemPackages which also sets HERMES_HOME
    environment.variables.HERMES_HOME = lib.mkIf (!useAgentStateDir) "/home/${cfg.user}/.hermes";

    # Create hermes state directory with proper config (only if not using agent state)
    system.activationScripts.hermes-cli-setup = lib.mkIf (!useAgentStateDir) (lib.stringAfter [ "users" ] ''
      HERMES_HOME="/home/${cfg.user}/.hermes"

      # Create directory structure
      mkdir -p "$HERMES_HOME"/{sessions,memories,skills,cron,logs}

      # Write config.yaml if it doesn't exist or is managed by us
      if [ ! -f "$HERMES_HOME/config.yaml" ] || grep -q "# Managed by NixOS" "$HERMES_HOME/config.yaml" 2>/dev/null; then
        cat > "$HERMES_HOME/config.yaml" << 'YAML_EOF'
# Managed by NixOS - hermes-cli module
model:
  provider: zai
  base_url: https://api.z.ai/api/coding/paas/v4
  default: ${cfg.model}
  api_key: none

providers:
  zai:
    base_url: https://api.z.ai/api/coding/paas/v4
    api_key_env: ZAI_API_KEY
    model: glm-5.1
  nvidia-nim:
    base_url: https://integrate.api.nvidia.com/v1
    api_key_env: NVIDIA_API_KEY
    model: deepseek-ai/deepseek-v3.1
  ai-gateway:
    base_url: http://127.0.0.1:8080/v1
    api_key: none
    model: qwen3.5-4b
  lmstudio:
    base_url: http://127.0.0.1:1234/v1
    api_key: lmstudio
    model: qwen3.5-4b
  llama-cpp-zephyr:
    base_url: http://llama-server-zephyr.ai-inference.svc.cluster.local:1235/v1
    api_key: unused
    model: Qwen3.6-35B-A3B-UD-Q3_K_M.gguf
  llama-cpp-sentry:
    base_url: http://llama-server-sentry.ai-inference.svc.cluster.local:1235/v1
    api_key: unused
    model: Qwen3.5-4B.Q4_K_M.gguf

fallback_providers:
  - zai
  - nvidia-nim
  - ai-gateway
  - llama-cpp-zephyr
  - llama-cpp-sentry

smart_model_routing:
  enabled: true
  max_simple_chars: 160
  max_simple_words: 28
  cheap_model:
    provider: llama-cpp-sentry
    model: Qwen3.5-4B.Q4_K_M.gguf

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
YAML_EOF
        chmod 644 "$HERMES_HOME/config.yaml"
      fi

      # Write .env with API keys from agenix secrets
      ${lib.optionalString (cfg.apiKeyFile != null) ''
        echo -n "# Hermes environment variables" > "$HERMES_HOME/.env"
        if [ -f "${cfg.apiKeyFile}" ]; then
          echo -n "ZAI_API_KEY=" >> "$HERMES_HOME/.env"
          cat "${cfg.apiKeyFile}" >> "$HERMES_HOME/.env"
          echo "" >> "$HERMES_HOME/.env"
        fi
        chmod 600 "$HERMES_HOME/.env"
      ''}
      ${lib.optionalString (cfg.nvidiaApiKeyFile != null) ''
        echo -n "NVIDIA_API_KEY=" >> "$HERMES_HOME/.env"
        if [ -f "${cfg.nvidiaApiKeyFile}" ]; then
          cat "${cfg.nvidiaApiKeyFile}" >> "$HERMES_HOME/.env"
          echo "" >> "$HERMES_HOME/.env"
        fi
        chmod 600 "$HERMES_HOME/.env"
      ''}

      # Write SOUL.md if it doesn't exist
      if [ ! -f "$HERMES_HOME/SOUL.md" ]; then
        cat > "$HERMES_HOME/SOUL.md" << 'SOUL_EOF'
${cfg.personality}
SOUL_EOF
        chmod 644 "$HERMES_HOME/SOUL.md"
      fi

      # Set ownership
      chown -R ${cfg.user}:users "$HERMES_HOME"
      chmod 750 "$HERMES_HOME"
    '');

    # Fish completions
    programs.fish.interactiveShellInit = lib.mkAfter ''
      # Hermes completions
      if command -v hermes &>/dev/null
        hermes completion fish 2>/dev/null | source
      end
    '';
  };
}

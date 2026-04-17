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

smart_model_routing:
  enabled: true
  max_simple_chars: 160
  max_simple_words: 28
  cheap_model:
    provider: llama-cpp
    model: gemma-4-e4b-it
YAML_EOF
        chmod 644 "$HERMES_HOME/config.yaml"
      fi

      # Write .env with API key from agenix secret
      ${lib.optionalString (cfg.apiKeyFile != null) ''
        if [ -f "${cfg.apiKeyFile}" ]; then
          cat > "$HERMES_HOME/.env" << ENV_EOF
ZAI_API_KEY=$(cat ${cfg.apiKeyFile})
ENV_EOF
          chmod 600 "$HERMES_HOME/.env"
        fi
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

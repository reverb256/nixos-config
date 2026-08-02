# Hermes Agent CLI module
#
# NOTE (issue #334): nixos-config no longer builds or installs the hermes-agent
# package. The NousResearch hermes-agent flake's `importNpmLock` offline prefetch
# of `@nous-research/ui` is broken (ENOTCACHED), which blocked all cluster
# builds/deploys. Hermes is instead installed via the user nix profile:
#
#     nix profile install github:NousResearch/hermes-agent
#
# so `hermes` is on the user's PATH from the profile. This module keeps the
# lightweight, Nix-managed pieces that don't require building the package:
#   - ~/.hermes SOUL.md + session/memory/skill directory tree
#   - fish shell completions (resolved via `command -v hermes` on PATH)
#   - the HERMES_HOME variable
#
# It no longer adds hermes to environment.systemPackages (the profile owns the
# binary) and wrappedHermesBin is null so home-manager skips the ~/.local/bin
# symlink (the profile binary is already on PATH).
#
# Usage:
#   services.hermes-cli.enable = true;
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.hermes-cli;

  # If hermes-agent is enabled, use its state dir. Otherwise, use user home.
  # (hermes-agent is no longer a nixos-config service, so this is effectively
  # always the user home now — kept for compatibility.)
  useHermesStateDir = false;
in {
  options.services.hermes-cli = {
    enable = lib.mkEnableOption "Hermes Agent CLI for interactive use";

    user = lib.mkOption {
      type = lib.types.str;
      default = "j_kro";
      description = "User who will run hermes CLI";
    };

    model = lib.mkOption {
      type = lib.types.str;
      default = "nvidia/nemotron-3-nano-30b-a3b";
      description = "Default model to use";
    };

    personality = lib.mkOption {
      type = lib.types.lines;
      default = ''
        You are Hermes Agent, an intelligent AI assistant created by Nous Research.
        You are helpful, knowledgeable, and direct. You assist users with a wide
        range of tasks including answering questions, writing and editing code, analyzing
        information, and creative work.
      '';
      description = " Agent personality (written to SOUL.md)";
    };

    secretspecEnvVarMappings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      example = lib.literalExpression ''
        {
          "NVIDIA_API_KEY"      = "NVIDIA_API_KEY";
          "OPENCODE_API_KEY"    = "OPENCODE_ZEN_API_KEY";
          "OPENCODE_GO_API_KEY" = "OPENCODE_GO_API_KEY";
          "HUGGINGFACE_TOKEN"   = "HUGGINGFACE_TOKEN";
          "GITHUB_TOKEN"        = "GITHUB_TOKEN";
        }
      '';
      description = ''
        Phase 2 (E2) migration path: map each SecretSpec route name (key)
        to the Hermes env var name (value).
      '';
    };

    nvidiaApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to sops-nix secret file containing NVIDIA_API_KEY";
    };

    opencodeGoApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to sops-nix secret file containing OpenCode Go API key";
    };

    opencodeZenApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to sops-nix secret file containing OpenCode Zen API key";
    };

    kilocodeApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to sops-nix secret file containing Kilo Code API key";
    };

    geminiApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to sops-nix secret file containing Gemini API key";
    };

    hfTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to sops-nix secret file containing HuggingFace token";
    };

    githubTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to sops-nix secret file containing GitHub token";
    };

    gatewayUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${config.networking.cluster.hosts.zephyr.ip}:${toString config.networking.cluster.kubernetes.nodePorts.ai-inference-gateway}/v1";
      description = "AI Inference Gateway URL for routing";
    };

    # Null: hermes is provided by the user nix profile, not nixos-config.
    # home-manager reads this and skips the ~/.local/bin/hermes symlink because
    # the profile binary is already on PATH.
    wrappedHermesBin = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      internal = true;
      readOnly = true;
      default = null;
      description = "Store path to the wrapped hermes binary. Null since hermes comes from the nix profile.";
    };

    managedConfig = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Emit selected top-level sections of config.yaml from Nix";
    };

    managedProviders = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = {};
      description = "Provider definitions mirroring the `providers:` block in hermes config.yaml";
    };

    managedFallbackProviders = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.str);
      default = [];
      description = "Ordered list of fallback provider entries matching `fallback_providers:` — each entry must be a dict with `provider` and `model` keys (bare strings are silently skipped by _iter_fallback_entries, verified 2026-08-02)";
    };

    voiceAutoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable voice mode (with TTS) by default on Hermes TUI startup.
      '';
    };
  };

  imports = [
    ./hermes-secrets.nix
    ./hermes-mcp.nix
    ./hermes-config-emit.nix
  ];

  config = lib.mkIf cfg.enable {
    # hermes binary comes from the user nix profile (issue #334) — do NOT add
    # a nixos-config-built package here.

    environment.variables.HERMES_HOME = "/home/${cfg.user}/.hermes";

    system.activationScripts.hermes-cli-setup = lib.stringAfter ["users"] ''
      HERMES_HOME="/home/${cfg.user}/.hermes"
      mkdir -p "$HERMES_HOME"/{sessions,memories,skills,cron,logs}
      mkdir -p "$HERMES_HOME/profiles/"/{analyst,backend-eng,frontend-eng,maplespike-eng-1,maplespike-eng-2,maplespike-eng-3,ops,researcher,writer}

      if [ ! -f "$HERMES_HOME/SOUL.md" ]; then
        cat > "$HERMES_HOME/SOUL.md" << 'SOUL_EOF'
      ${cfg.personality}
      SOUL_EOF
        chmod 644 "$HERMES_HOME/SOUL.md"
      fi

      chown -R ${cfg.user}:users "$HERMES_HOME" 2>/dev/null || true
      chmod 750 "$HERMES_HOME" 2>/dev/null || true
    '';

    programs.fish.interactiveShellInit = lib.mkAfter ''
      # Hermes completions (resolved via profile `hermes` on PATH)
      if command -v hermes &>/dev/null
        hermes completion fish 2>/dev/null | grep -v '^SITECUSTOMIZE:' | source
      end
    '';
  };
}

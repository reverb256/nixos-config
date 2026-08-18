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
      # NOTE: Hermes v0.20.0 get_fallback_chain() requires each entry to be a
      # dict with provider+model; plain strings are SILENTLY SKIPPED (an empty
      # chain). The emitter writes this list verbatim into config.yaml, so the
      # option must hold dicts, not names.
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      default = [];
      example = lib.literalExpression ''
        [
          { provider = "switchyard"; model = "switchyard/local"; }
          { provider = "opencode-zen"; model = "nemotron-3.5-lightning-free"; }
        ]
      '';
      description = "Ordered fallback chain matching `fallback_providers:` (list of {provider, model} dicts).";
    };

    # A2A mesh peers — mirrors the `a2a_agents:` block in hermes config.yaml.
    # Dendritic SPOC: peers come from Nix, never hand-edited (the emitter
    # rewrites this key at boot). Each attr = one peer (name, url, auth,
    # timeout, capabilities list). NOTE: capabilities must be a LIST, not a
    # quoted string (see hermes-a2a-mesh skill — char-split rendering bug).
    managedA2aAgents = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = {};
      example = lib.literalExpression ''
        {
          hermes-nexus = {
            url = "http://10.1.1.120:9900";
            auth = { type = "bearer"; token = "REDACTED"; };
            timeout = 300;
            capabilities = [ "infra" "build" "ai" ];
          };
        }
      '';
      description = "A2A peer definitions mirroring the `a2a_agents:` block in hermes config.yaml.";
    };

    # gateway.platforms.a2a — enables the inbound A2A platform for this host.
    managedGatewayA2a = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = null;
      example = lib.literalExpression ''
        {
          enabled = true;
          extra = { port = 9900; };
        }
      '';
      description = "gateway.platforms.a2a section for hermes config.yaml (null = not managed).";
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

    # The profile installs hermes as SPLIT packages (hermes-agent-env, hermes-tui,
    # hermes-web, hermes-desktop) — bin/hermes is the RAW env script, so the
    # upstream wrapper's HERMES_TUI_DIR wiring (nix/hermes-agent.nix sets it via
    # makeWrapper) is never applied. Without it, `hermes --tui`/`--resume` fails
    # with "TUI workspace is missing from this Hermes checkout".
    #
    # Point at ~/.nix-profile/lib/hermes-tui (symlink to the CURRENT profile
    # generation) instead of a store path — self-healing across `nix profile
    # upgrade`, same pattern as the hermes-gateway unit's %h/.nix-profile.
    # Resolved in _make_tui_argv before any checkout probe.
    #
    # NOTE: INACTIVE on zephyr — services.hermes-cli.enable = false there
    # (the hosts/zephyr/services.nix block is dead code, see
    # hosts/zephyr/configuration.nix). The active zephyr path is the fish
    # conf.d export in home-manager-config/modules/hermes-gateway.nix
    # (~/.config/fish/conf.d/hermes-tui.fish).
    environment.variables.HERMES_TUI_DIR = "/home/${cfg.user}/.nix-profile/lib/hermes-tui";

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

    programs.zsh.interactiveShellInit = lib.mkAfter ''
      # Hermes completions (resolved via profile `hermes` on PATH)
      if command -v hermes &>/dev/null; then
        source <(hermes completion zsh 2>/dev/null)
      fi
    '';
  };
}

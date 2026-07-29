# Hermes Agent CLI module
#
# Installs the hermes CLI tool for interactive use on any host.
# Each host gets its own ~/.hermes/ state directory with unified config
# (same model, tools, personality everywhere via Nix-managed providers).
#
# Phase 3 de-monolith (2026-07-29): 3 systemd services extracted.
#   ./hermes-secrets.nix      — hermes-config-secrets (sops-nix + secretspec)
#   ./hermes-mcp.nix          — hermes-mcp-servers (MCP registry merge)
#   ./hermes-config-emit.nix  — Nix-managed config.yaml emission
#
# Usage:
#   services.hermes-cli.enable = true;
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.services.hermes-cli;
  hermesAgentCfg = config.services.hermes-agent or {};

  # Runtime library path for audio (PortAudio) on NixOS.
  hermesAudioLibPath = lib.makeLibraryPath [
    pkgs.portaudio
    pkgs.alsa-lib
  ];

  # Python runtime path for voice-mode packages (sounddevice, numpy).
  hermesVoicePyPath = lib.makeSearchPath "lib/python3.12/site-packages" [
    pkgs.python3Packages.sounddevice
    pkgs.python3Packages.numpy
  ];

  # Patch hermes-agent to remove /etc/ from sensitive path blocklist.
  hermesPkg = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
    postInstall =
      (old.postInstall or "")
      + ''
        SITE_PKGS=""
        HERMES_PY=$(grep -oP 'export HERMES_PYTHON=\\K\"\\K[^\"]+' "$out/bin/hermes" 2>/dev/null | head -1 || true)
        if [ -n "$HERMES_PY" ]; then
          ENV_DIR=$(dirname "$(dirname "$HERMES_PY")")
          for sp in "$ENV_DIR"/lib/python*/site-packages; do
            if [ -d "$sp/tools" ]; then SITE_PKGS="$sp"; break; fi
          done
        fi
        if [ -z "$SITE_PKGS" ]; then
          for sp in "$out"/lib/*/site-packages; do
            if [ -d "$sp/tools" ]; then SITE_PKGS="$sp"; break; fi
          done
        fi
        if [ -z "$SITE_PKGS" ]; then
          echo "WARNING: Could not find site-packages with tools/ dir — skipping patches"
        else
          echo "Patching hermes-agent Python files in: $SITE_PKGS"

        if [ -f "$SITE_PKGS/tools/file_tools.py" ]; then
          substituteInPlace "$SITE_PKGS/tools/file_tools.py" \
            --replace-fail \
            '"/etc/", "/boot/", "/usr/lib/systemd/"' \
            '"/boot/", "/usr/lib/systemd/"'
        fi

        if [ -f "$SITE_PKGS/hermes_cli/models.py" ]; then
          substituteInPlace "$SITE_PKGS/hermes_cli/models.py" \
            --replace-fail \
            '                    # Merge static curated list with live API results so\n                    # models that the live endpoint omits (stale cache,\n                    # partial rollout) still appear in the picker.' \
            '                    # NVIDIA NIM returns ~124 models but many are non-agentic\n                    # (embedding, guard, safety, rerank, reward). Filter them out.\n                    if normalized == "nvidia":\n                        live = [m for m in live if _is_agentic_nvidia_model(m)]\n                    # Merge static curated list with live API results so\n                    # models that the live endpoint omits (stale cache,\n                    # partial rollout) still appear in the picker.'
          substituteInPlace "$SITE_PKGS/hermes_cli/models.py" \
            --replace-fail \
            '\n# ---------------------------------------------------------------------------\n# Generic disk cache for provider_model_ids()' \
            '\n\ndef _is_agentic_nvidia_model(m: str) -> bool:\n    """Filter NVIDIA NIM models to only agentic chat/reasoning models."""\n    lower = m.lower()\n    non_agentic = ["bge-", "e5-", "jina-", "nvolve-", "rerank", "reward",\n                   "nemoguard", "guard", "safety", "starcoder", "fuyu",\n                   "phi-3-vision", "phi-4-vision", "bce", "gte-", "sea-lion"]\n    return not any(p in lower for p in non_agentic)\n\n\n# ---------------------------------------------------------------------------\n# Generic disk cache for provider_model_ids()'
        fi
        fi
      '';
  });

  # Wrap hermes-agent so every bin gets LD_LIBRARY_PATH + PYTHONPATH.
  hermesPkgWrapped =
    pkgs.runCommand "hermes-agent-wrapped-${hermesPkg.version or "0.18.0"}" {
      nativeBuildInputs = [pkgs.makeWrapper];
      buildInputs = [hermesPkg];
      meta = (hermesPkg.meta or {}) // {description = "hermes-agent with PortAudio LD_LIBRARY_PATH wrapper";};
    } ''
      mkdir -p "$out/bin"
      ${lib.optionalString cfg.voiceAutoStart
        "VOICE_ARGS='--set HERMES_VOICE 1 --set HERMES_VOICE_TTS 1'"}
      ${lib.optionalString (!cfg.voiceAutoStart) "VOICE_ARGS=''"}

      for bin in ${hermesPkg}/bin/*; do
        name=$(basename "$bin")
        makeWrapper "$bin" "$out/bin/$name" \
          --prefix LD_LIBRARY_PATH : "${hermesAudioLibPath}" \
          --prefix PYTHONPATH : "${hermesVoicePyPath}" $VOICE_ARGS
      done
    '';

  wrappedBinPath = "${hermesPkgWrapped}/bin/hermes";

  # apiKeyFile/ZAI_API_KEY removed 2026-07-15. Z.AI is fully gone from the
  # cluster — no Z.AI MCP servers, no Z.AI LLM provider, no Z.AI secrets.
  # buffy-mcp + local bridges don't need internet bearer auth.

  # Use base hermes-agent package without WhatsApp bridge (stub removed).
  # WhatsApp functionality temporarily disabled.

  # If hermes-agent is enabled, use its state dir. Otherwise, use user home.
  useAgentStateDir = hermesAgentCfg.enable or false;
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
        You are helpful, knowledgeable, and direct. You assist users with a wide range
        of tasks including answering questions, writing and editing code, analyzing
        information, and creative work.
      '';
      description = "Agent personality (written to SOUL.md)";
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

    wrappedHermesBin = lib.mkOption {
      type = lib.types.str;
      internal = true;
      readOnly = true;
      default = wrappedBinPath;
      description = "Store path to the wrapped hermes binary with PortAudio LD_LIBRARY_PATH.";
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
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Ordered list of fallback providers matching `fallback_providers:`";
    };

    voiceAutoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable voice mode (with TTS) by default on Hermes TUI startup.
        Implemented by injecting HERMES_VOICE=1 + HERMES_VOICE_TTS=1 into
        the wrapped hermes binaries.
      '';
    };
  };

  imports = [
    ./hermes-secrets.nix
    ./hermes-mcp.nix
    ./hermes-config-emit.nix
  ];

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [hermesPkgWrapped];

    environment.variables.HERMES_HOME = lib.mkIf (!useAgentStateDir) "/home/${cfg.user}/.hermes";

    system.activationScripts.hermes-cli-setup = lib.mkIf (!useAgentStateDir) (
      lib.stringAfter ["users"] ''
        HERMES_HOME="/home/${cfg.user}/.hermes"
        mkdir -p "$HERMES_HOME"/{sessions,memories,skills,cron,logs}
        mkdir -p "$HERMES_HOME/profiles/"{analyst,backend-eng,frontend-eng,maplespike-eng-1,maplespike-eng-2,maplespike-eng-3,ops,researcher,writer}

        if [ ! -f "$HERMES_HOME/SOUL.md" ]; then
          cat > "$HERMES_HOME/SOUL.md" << 'SOUL_EOF'
        ${cfg.personality}
        SOUL_EOF
          chmod 644 "$HERMES_HOME/SOUL.md"
        fi

        chown -R ${cfg.user}:users "$HERMES_HOME" 2>/dev/null || true
        chmod 750 "$HERMES_HOME" 2>/dev/null || true
      ''
    );

    programs.fish.interactiveShellInit = lib.mkAfter ''
      # Hermes completions
      if command -v hermes &>/dev/null
        hermes completion fish 2>/dev/null | grep -v '^SITECUSTOMIZE:' | source
      end
    '';
  };
}

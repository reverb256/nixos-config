# Hermes Agent CLI module
#
# Installs the hermes CLI tool for interactive use on any host.
# Each host gets its own ~/.hermes/ state directory with unified config
# (same model, tools, personality everywhere via Nix-managed providers).
#
# On hosts where services.hermes-agent is enabled, this module only installs
# the package and fish completions - the hermes-agent module handles HERMES_HOME
# and state directory setup.
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
  # NixOS has no ldconfig / /etc/ld.so.cache, so ctypes.util.find_library()
  # returns None and sounddevice raises "PortAudio library not found".
  # sounddevice only strips to 'libportaudio' (not '.so.2'), so even the
  # system-path symlink isn't found by the loader. The fix is to prefix
  # LD_LIBRARY_PATH with the portaudio + alsa-lib lib dirs on every hermes
  # wrapper, so dlopen() resolves them. This is the canonical pattern already
  # proven in packages/hermes-with-whatsapp.nix (now dead code).
  hermesAudioLibPath = lib.makeLibraryPath [
    pkgs.portaudio
    pkgs.alsa-lib
  ];

  # Patch hermes-agent to remove /etc/ from sensitive path blocklist,
  # allowing write_file and patch tools to edit /etc/nixos/ files.
  hermesPkg = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
    # Hermes 0.17.0+ splits Python into a separate hermes-agent-env derivation.
    # The wrapper ($out) only has bin/ wrappers; the actual .py files live in
    # the env derivation referenced via $HERMES_PYTHON in the wrapper script.
    # We resolve the site-packages dir from the env's python path so the patches
    # work regardless of how upstream structures the derivation.
    postInstall = (old.postInstall or "") + ''
      # Find the Python site-packages directory.
      # Try the env derivation first (0.17.0+), then fall back to $out (older).
      SITE_PKGS=""
      # Method 1: Resolve from the wrapper's HERMES_PYTHON export
      HERMES_PY=$(grep -oP 'export HERMES_PYTHON=\K"\K[^"]+' "$out/bin/hermes" 2>/dev/null | head -1 || true)
      if [ -n "$HERMES_PY" ]; then
        ENV_DIR=$(dirname "$(dirname "$HERMES_PY")")
        for sp in "$ENV_DIR"/lib/python*/site-packages; do
          if [ -d "$sp/tools" ]; then SITE_PKGS="$sp"; break; fi
        done
      fi
      # Method 2: Fall back to $out (pre-0.17.0 layout)
      if [ -z "$SITE_PKGS" ]; then
        for sp in "$out"/lib/*/site-packages; do
          if [ -d "$sp/tools" ]; then SITE_PKGS="$sp"; break; fi
        done
      fi
      if [ -z "$SITE_PKGS" ]; then
        echo "WARNING: Could not find site-packages with tools/ dir — skipping patches"
      else
        echo "Patching hermes-agent Python files in: $SITE_PKGS"

      # Remove "/etc/" from _SENSITIVE_PATH_PREFIXES so write_file/patch can
      # edit files under /etc/nixos/ directly (instead of falling back to sed).
      # The file_operations.py deny-list still blocks /etc/sudoers, /etc/passwd,
      # /etc/shadow, /etc/systemd, and /etc/sudoers.d for defense-in-depth.
      if [ -f "$SITE_PKGS/tools/file_tools.py" ]; then
        substituteInPlace "$SITE_PKGS/tools/file_tools.py" \
          --replace-fail \
          '"/etc/", "/boot/", "/usr/lib/systemd/"' \
          '"/boot/", "/usr/lib/systemd/"'
      fi

      # NOTE: cua-driver backend Linux support + windows pid=None guard are
      # now merged upstream (hermes-agent >= f341cadb). Patch dropped 2026-07-07.

      # Patch nvidia model picker: filter out 100+ non-agentic models
      # (embedding, guard, safety, rerank, reward) from the model picker.
      # Only agentic chat/reasoning models appear when selecting nvidia models.
      if [ -f "$SITE_PKGS/hermes_cli/models.py" ]; then
        substituteInPlace "$SITE_PKGS/hermes_cli/models.py" \
          --replace-fail \
          '                    # Merge static curated list with live API results so\n                    # models that the live endpoint omits (stale cache,\n                    # partial rollout) still appear in the picker.' \
          '                    # NVIDIA NIM returns ~124 models but many are non-agentic\n                    # (embedding, guard, safety, rerank, reward). Filter them out.\n                    if normalized == "nvidia":\n                        live = [m for m in live if _is_agentic_nvidia_model(m)]\n                    # Merge static curated list with live API results so\n                    # models that the live endpoint omits (stale cache,\n                    # partial rollout) still appear in the picker.'
        # Add the filter function before the disk cache section
        substituteInPlace "$SITE_PKGS/hermes_cli/models.py" \
          --replace-fail \
          '\n# ---------------------------------------------------------------------------\n# Generic disk cache for provider_model_ids()' \
          '\n\ndef _is_agentic_nvidia_model(m: str) -> bool:\n    """Filter NVIDIA NIM models to only agentic chat/reasoning models."""\n    lower = m.lower()\n    non_agentic = ["bge-", "e5-", "jina-", "nvolve-", "rerank", "reward",\n                   "nemoguard", "guard", "safety", "starcoder", "fuyu",\n                   "phi-3-vision", "phi-4-vision", "bce", "gte-", "sea-lion"]\n    return not any(p in lower for p in non_agentic)\n\n\n# ---------------------------------------------------------------------------\n# Generic disk cache for provider_model_ids()'
      fi
      fi
    '';
  });

  # Wrap hermes-agent so every bin (hermes, hermes-agent, hermes-acp) gets
  # LD_LIBRARY_PATH for PortAudio + alsa-lib. On NixOS there is no ldconfig,
  # so ctypes.util.find_library('portaudio') returns None and sounddevice
  # raises OSError("PortAudio library not found") -> Hermes refuses to start
  # voice mode. Prefixing LD_LIBRARY_PATH makes dlopen('libportaudio') resolve.
  # This is the canonical fix; the equivalent lived in the now-dead
  # packages/hermes-with-whatsapp.nix (--prefix LD_LIBRARY_PATH : portaudioLib).
  hermesPkgWrapped = pkgs.runCommand "hermes-agent-wrapped-${hermesPkg.version or "0.18.0"}" {
    nativeBuildInputs = [ pkgs.makeWrapper ];
    buildInputs = [ hermesPkg ];
    meta = (hermesPkg.meta or {}) // { description = "hermes-agent with PortAudio LD_LIBRARY_PATH wrapper"; };
  } ''
    mkdir -p "$out/bin"
    # Voice mode on by default (services.hermes-cli.voiceAutoStart):
    # the Hermes TUI gateway honors HERMES_VOICE=1 (voice mode) and
    # HERMES_VOICE_TTS=1 (speak replies) as its native "voice on by default"
    # hook. No config.yaml key does this in hermes-agent 0.18.x.
    ${lib.optionalString cfg.voiceAutoStart
      "VOICE_ARGS=''--set HERMES_VOICE 1 --set HERMES_VOICE_TTS 1''"}
    ${lib.optionalString (!cfg.voiceAutoStart) "VOICE_ARGS=''"}

    for bin in ${hermesPkg}/bin/*; do
      name=$(basename "$bin")
      makeWrapper "$bin" "$out/bin/$name" \
        --prefix LD_LIBRARY_PATH : "${hermesAudioLibPath}" $VOICE_ARGS
    done
  '';

  # Expose the wrapped hermes bin dir so Home Manager (user-local symlink)
  # and other modules can reference it by store path without touching
  # /run/current-system at pure-eval time.
  wrappedBinPath = "${hermesPkgWrapped}/bin/hermes";

  # apiKeyFile/ZAI_API_KEY removed 2026-07-15. Z.AI is fully gone from the
  # cluster — no Z.AI MCP servers, no Z.AI LLM provider, no Z.AI secrets.
  # buffy-mcp + local bridges don't need internet bearer auth.

  # Use base hermes-agent package without WhatsApp bridge (stub removed)
  # WhatsApp functionality temporarily disabled

  # If hermes-agent is enabled, use its state dir. Otherwise, use user home.
  useAgentStateDir = hermesAgentCfg.enable or false;

  # ── MCP server list: registry is the single source of truth ────────────
  # The legacy in-tree fallback block (~75 lines, hardcoded MCP servers)
  # was deleted 2026-07-15 along with the dropped MCP servers (Z.AI +
  # Casdoor bridge). Add/remove MCP servers in modules/services/mcp-server-registry.nix
  # ONLY — this module consumes config.lib.mcp-registry.hermesMcpYaml.
  useRegistry = config.services.mcp-registry.enable or false;

  # ruamel.yaml round-trip merge into Hermes config.yaml. Replaces the
  # line-by-line parser which broke on:
  #   - top-level `mcp_servers:` keys nested deeper in the document
  #   - YAML comments / quoted strings containing "mcp_servers:"
  #   - multi-line scalars / flow-style maps
  # ruamel preserves comments, ordering, and key structure on round-trip.
  mcpMergeScript = pkgs.writeText "hermes-mcp-merge.py" ''
    import os
    import shutil
    import sys
    import time
    from ruamel.yaml import YAML

    config_path = sys.argv[1]
    mcp_path = sys.argv[2]

    yaml = YAML()
    yaml.indent(mapping=2, sequence=4, offset=2)
    yaml.preserve_quotes = True

    # config.yaml handling:
    #   - missing or empty → start with empty dict (mcp_servers-only merge)
    #   - parse error → BACKUP original to .bak.<ts> and BAIL. Silent
    #     overwrite would WIPE the rest of the user's config.yaml
    #     (providers, fallback_providers, smart_model_routing, etc.).
    if os.path.exists(config_path):
        try:
            with open(config_path) as f:
                data = yaml.load(f) or {}
        except Exception as e:
            ts = int(time.time())
            backup = f"{config_path}.bak.{ts}"
            shutil.copy2(config_path, backup)
            print(f"[hermes-mcp] FATAL: config.yaml parse failed: {e}", file=sys.stderr)
            print(f"[hermes-mcp] backed up to {backup}; refusing to overwrite", file=sys.stderr)
            sys.exit(1)
    else:
        data = {}

    # mcp block is a Nix store path produced by pkgs.writeText + mkHermesMcpServers.
    # If it's malformed, that's a Nix bug — let the raw YAMLError propagate so the
    # trace is honest. We still guard on missing file + empty mcp_servers mapping.
    if not os.path.exists(mcp_path):
        print(f"[hermes-mcp] FATAL: mcp block not found at {mcp_path}", file=sys.stderr)
        sys.exit(1)
    with open(mcp_path) as f:
        mcp_data = yaml.load(f) or {}
    if not mcp_data.get("mcp_servers"):
        print(f"[hermes-mcp] FATAL: mcp block has no mcp_servers mapping", file=sys.stderr)
        sys.exit(1)

    if "mcp_servers" in mcp_data:
        data["mcp_servers"] = mcp_data["mcp_servers"]

    with open(config_path, "w") as f:
        yaml.dump(data, f)
  '';
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

    # Note: there is intentionally no `useRegistry` option. The systemd
    # gate is derived directly from services.mcp-registry.enable (let
    # binding below). An override option was removed 2026-07-15 because
    # it created an edge case where hermes-cli could reference
    # config.lib.mcp-registry.hermesMcpYaml before mcp-registry was
    # enabled (Nix eval failure).

    nvidiaApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to sops-nix secret file containing NVIDIA_API_KEY";
      example = "config.age.secrets.nvidia-api-key.path";
    };


    opencodeGoApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to sops-nix secret file containing OpenCode Go API key";
      example = "config.age.secrets.opencode-go-api-key.path";
    };

    opencodeZenApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to sops-nix secret file containing OpenCode Zen API key";
      example = "config.age.secrets.opencode-api-key.path";
    };

    kilocodeApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to sops-nix secret file containing Kilo Code API key";
      example = "config.age.secrets.kilo-api-key.path";
    };

    geminiApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to sops-nix secret file containing Gemini API key";
      example = "config.age.secrets.gemini-api-key.path";
    };

    hfTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to sops-nix secret file containing HuggingFace token";
      example = "config.age.secrets.huggingface-token.path";
    };

    githubTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to sops-nix secret file containing GitHub token";
      example = "config.age.secrets.github-token.path";
    };

    gatewayUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${config.networking.cluster.hosts.zephyr.ip}:${toString config.networking.cluster.kubernetes.nodePorts.ai-inference-gateway}/v1";
      description = "AI Inference Gateway URL for routing";
    };

    # ── Nix-managed config.yaml emitters ──────────────────────────
    # When managedConfig = true, the module synthesizes top-level
    # sections (providers, fallback_providers, model) of config.yaml at
    # boot from Nix expressions. Imperative sections (mcp_servers,
    # gateway.platforms.telegram.channel_profiles, skills, etc.) on disk
    # are preserved verbatim across rebuilds.
    # Internal: store-path to the wrapped hermes binary (carries the
    # PortAudio LD_LIBRARY_PATH). Exposed to Home Manager via extraSpecialArgs
    # so the user-local ~/.local/bin/hermes symlink tracks the real path.
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
      description = "Emit selected top-level sections of /var/lib/hermes/.hermes/config.yaml from Nix";
    };

    managedProviders = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = {};
      example = lib.literalExpression ''
        {
          "opencode-zen" = {
            api_key_env = "OPENCODE_API_KEY";
            base_url = "https://opencode.ai/zen/v1";
            discover_models = true;
            model = "nvidia/nemotron-3-nano-30b-a3b";
          };
        }
      '';
      description = "Provider definitions mirroring the `providers:` block in hermes config.yaml";
    };

    managedFallbackProviders = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ''["opencode-zen" "opencode-go" "nvidia"]'';
      description = "Ordered list of fallback providers matching `fallback_providers:` in hermes config.yaml";
    };

    voiceAutoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable voice mode (with TTS) by default on Hermes TUI startup.

        Implemented by injecting HERMES_VOICE=1 + HERMES_VOICE_TTS=1 into the
        wrapped hermes binaries. The TUI gateway (tui_gateway/server.py::
        _voice_mode_enabled / _voice_tts_enabled) treats these env vars as the
        authoritative voice-mode / TTS flags; hermes-agent 0.18.x has NO
        config.yaml key that auto-enables voice at startup. Set false to
        require an explicit `/voice on` each session.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Install hermes package system-wide. Use the wrapped variant so voice
    # mode's PortAudio dependency resolves (LD_LIBRARY_PATH for portaudio +
    # alsa-lib). The bare pkgs.portaudio is no longer needed here.
    environment.systemPackages = [hermesPkgWrapped];

    # Only set HERMES_HOME if hermes-agent is NOT managing it
    # The hermes-agent module sets addToSystemPackages which also sets HERMES_HOME
    environment.variables.HERMES_HOME = lib.mkIf (!useAgentStateDir) "/home/${cfg.user}/.hermes";
    # LD_LIBRARY_PATH managed by host-specific hardware.nix (ROCm + audio)
    # hermes-cli no longer sets it directly to avoid conflicts

    # Create hermes state directory with proper config (only if not using agent state)
    system.activationScripts.hermes-cli-setup = lib.mkIf (!useAgentStateDir) (
      lib.stringAfter ["users"] ''
                      HERMES_HOME="/home/${cfg.user}/.hermes"

                      # Create directory structure
                      mkdir -p "$HERMES_HOME"/{sessions,memories,skills,cron,logs}

                      # Scaffold per-profile dirs so the 10-profile loop in
                      # hermes-mcp-servers no longer no-ops. The dirs are
                      # safe to leave empty; users populate ~/.hermes/profiles/
                      # as they onboard new profiles.
                      mkdir -p "$HERMES_HOME/profiles/"{analyst,backend-eng,frontend-eng,maplespike-eng-1,maplespike-eng-2,maplespike-eng-3,ops,researcher,writer}

                                            # Write SOUL.md if it doesn't exist
                      if [ ! -f "$HERMES_HOME/SOUL.md" ]; then
          cat > "$HERMES_HOME/SOUL.md" << 'SOUL_EOF'
          ${cfg.personality}
        SOUL_EOF
                        chmod 644 "$HERMES_HOME/SOUL.md"
                      fi

                      # Set ownership (skip on NFS where root-squash blocks chown)
                      chown -R ${cfg.user}:users "$HERMES_HOME" 2>/dev/null || true
                      chmod 750 "$HERMES_HOME" 2>/dev/null || true
      ''
    );

    # Fish completions
    programs.fish.interactiveShellInit = lib.mkAfter ''
      # Hermes completions
      if command -v hermes &>/dev/null
        hermes completion fish 2>/dev/null | grep -v '^SITECUSTOMIZE:' | source
      end
    '';

    # Inject sops-nix secrets into Hermes config at boot
    systemd.services.hermes-config-secrets = lib.mkIf (
cfg.nvidiaApiKeyFile != null
      || cfg.opencodeGoApiKeyFile != null
      || cfg.opencodeZenApiKeyFile != null
      || cfg.kilocodeApiKeyFile != null
      || cfg.geminiApiKeyFile != null
      || cfg.hfTokenFile != null
      || cfg.githubTokenFile != null
    ) {
      description = "Inject sops-nix secrets into Hermes config";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      path = with pkgs; [coreutils gnused gnugrep];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        RemainAfterExit = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = ["/home/${cfg.user}/.hermes"];

        ExecStart = pkgs.writeShellScript "hermes-config-secrets" ''
          set -euo pipefail

          HERMES_CONFIG="/home/${cfg.user}/.hermes/config.yaml"

          if [ ! -f "$HERMES_CONFIG" ]; then
            echo "[hermes-config] No config.yaml found, skipping"
            exit 0
          fi

          # Ensure all base_url entries point to gateway (prevents stale IPs)
          # Casdoor JWT injection removed 2026-07-15 (casdoor MCP dropped —
          # see modules/services/mcp-server-registry.nix + ACTION-ITEMS P2-5).

          # Ensure all base_url entries point to gateway (prevents stale IPs)
          GATEWAY_URL="${cfg.gatewayUrl}"
          # Fix any remaining direct Sentry or stale pod IPs
          sed -i "s|base_url: http://10\.1\.1\.140:1235/v1|base_url: $GATEWAY_URL|g" "$HERMES_CONFIG"
          sed -i "s|base_url: http://10\.4\.[0-9]*\.[0-9]*:1235/v1|base_url: $GATEWAY_URL|g" "$HERMES_CONFIG"
          # Fix any corrupted [IP_ADDRESS] placeholders from previous sed failures
          sed -i "s|base_url: http://\[IP_ADDRESS\]:8080/v1|base_url: $GATEWAY_URL|g" "$HERMES_CONFIG"

          # Enforce Z.AI coding plan endpoint (not pay-as-you-go /api/paas/v4)
          # Also catch the exact pay-as-you-go path without trailing chars

          chown ${cfg.user}:users "$HERMES_CONFIG" 2>/dev/null || true
          chmod 600 "$HERMES_CONFIG" 2>/dev/null || true

          # ── Export sops-nix secrets to $HERMES_HOME/.env ──────────
          # Hermes reads .env at startup for env vars like OPENCODE_API_KEY,
          # OPENCODE_ZEN_API_KEY, etc. We maintain the file here from sops-nix
          # secrets so it survives Hermes Vault bootstrap cycles.
          ENV_FILE="/home/${cfg.user}/.hermes/.env"

          # opencodeZenApiKeyFile → OPENCODE_API_KEY + OPENCODE_ZEN_API_KEY
          ${lib.optionalString (cfg.opencodeZenApiKeyFile != null) ''
            OC_ZEN="${cfg.opencodeZenApiKeyFile}"
            if [ -f "$OC_ZEN" ] && [ -s "$OC_ZEN" ]; then
              ZEN_KEY="$(cat "$OC_ZEN")"
              # Remove any stale OPENCODE_ZEN_API_KEY line (including vault-redacted comments)
              grep -v '^OPENCODE_ZEN_API_KEY=\\|^#.*OPENCODE_ZEN_API_KEY=' "$ENV_FILE" > "$ENV_FILE".tmp 2>/dev/null || true
              echo "OPENCODE_ZEN_API_KEY=$ZEN_KEY" >> "$ENV_FILE".tmp
              sort -u "$ENV_FILE".tmp > "$ENV_FILE"
              chmod 600 "$ENV_FILE"
              chown ${cfg.user}:users "$ENV_FILE" 2>/dev/null || true
              echo "[hermes-config] ✓ OPENCODE_ZEN_API_KEY written to .env"
            fi
          ''}

          ${lib.optionalString (cfg.opencodeGoApiKeyFile != null) ''
            OC_GO="${cfg.opencodeGoApiKeyFile}"
            if [ -f "$OC_GO" ] && [ -s "$OC_GO" ]; then
              GO_KEY="$(cat "$OC_GO")"
              grep -v '^OPENCODE_GO_API_KEY=\\|^#.*OPENCODE_GO_API_KEY=' "$ENV_FILE" > "$ENV_FILE".tmp 2>/dev/null || true
              echo "OPENCODE_GO_API_KEY=$GO_KEY" >> "$ENV_FILE".tmp
              sort -u "$ENV_FILE".tmp > "$ENV_FILE"
              chmod 600 "$ENV_FILE"
              chown ${cfg.user}:users "$ENV_FILE" 2>/dev/null || true
              echo "[hermes-config] ✓ OPENCODE_GO_API_KEY written to .env"
            fi
          ''}

          ${lib.optionalString (cfg.nvidiaApiKeyFile != null) ''
            NV_KEY_PATH="${cfg.nvidiaApiKeyFile}"
            if [ -f "$NV_KEY_PATH" ] && [ -s "$NV_KEY_PATH" ]; then
              NV_KEY="$(cat "$NV_KEY_PATH")"
              grep -v '^NVIDIA_API_KEY=\\|^#.*NVIDIA_API_KEY=' "$ENV_FILE" > "$ENV_FILE".tmp 2>/dev/null || true
              echo "NVIDIA_API_KEY=$NV_KEY" >> "$ENV_FILE".tmp
              sort -u "$ENV_FILE".tmp > "$ENV_FILE"
              chmod 600 "$ENV_FILE"
              chown ${cfg.user}:users "$ENV_FILE" 2>/dev/null || true
              echo "[hermes-config] ✓ NVIDIA_API_KEY written to .env"
            fi
          ''}

          # Ensure .env exists even if no secrets were configured
          touch "$ENV_FILE"
          chmod 600 "$ENV_FILE" 2>/dev/null || true

          echo "[hermes-config] Done"
        '';
      };
    };

    # ── Declarative MCP server management ─────────────────────────
    # Merges Nix-defined mcp_servers into Hermes config.yaml at boot.
    # API keys are injected from sops-nix secrets.
    systemd.services.hermes-mcp-servers = lib.mkIf useRegistry {
      restartIfChanged = true;
      description = "Inject declarative MCP servers into Hermes config (from mcp-server-registry)";
      # Order matters: hermes-config-secrets populates ~/.hermes/.env from
      # sops-nix secrets before this unit runs the merge.
      after = ["network.target" "hermes-config-secrets.service"];
      wantedBy = ["multi-user.target"];

      # python3-with-ruamel for the ruamel.yaml round-trip merge script.
      # python3-with-ruamel for the ruamel.yaml round-trip merge script.
      path = with pkgs; [(python3.withPackages (p: [p.ruyaml])) coreutils gnused];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        RemainAfterExit = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = ["/home/${cfg.user}/.hermes"];

        ExecStart = pkgs.writeShellScript "hermes-mcp-servers" ''
          set -euo pipefail

          for profile in "" analyst backend-eng frontend-eng maplespike-eng-1 maplespike-eng-2 maplespike-eng-3 ops researcher writer; do
            if [ -z "$profile" ]; then
              HERMES_CONFIG="/home/${cfg.user}/.hermes/config.yaml"
            else
              HERMES_CONFIG="/home/${cfg.user}/.hermes/profiles/$profile/config.yaml"
            fi

            if [ ! -f "$HERMES_CONFIG" ]; then
              echo "[hermes-mcp] No config.yaml for profile '$profile', skipping"
              continue
            fi

            echo "[hermes-mcp] Processing profile: $profile"

            # Pull Nix-managed mcp_servers directly from the registry
            # (single source of truth). See modules/services/mcp-server-registry.nix.
            MCP_TMP=$(mktemp /tmp/hermes-mcp-XXXXXX.yaml)
            cp ${config.lib.mcp-registry.hermesMcpYaml} "$MCP_TMP"

            # Merge into config.yaml using ruamel.yaml round-trip — preserves
            # comments, ordering, and key structure (replaces fragile line-by-line parser).
            python3 ${mcpMergeScript} "$HERMES_CONFIG" "$MCP_TMP"
            rm -f "$MCP_TMP"

            chown ${cfg.user}:users "$HERMES_CONFIG" 2>/dev/null || true
            chmod 600 "$HERMES_CONFIG" 2>/dev/null || true

            echo "[hermes-mcp] ✓ MCP servers configured for profile: $profile"
          done
        '';
      };
    };
    # ── Nix-managed config.yaml emitter ────────────────────────────
    # At boot, rewrite the top-level blocks owned by Nix:
    #   - providers:
    #   - fallback_providers:
    # All other top-level keys (mcp_servers, gateway, skills,
    # smart_model_routing, display, auxiliary, compression, etc.) are
    # preserved as-is.
    #
    # Idempotent: writes only if the would-be hash differs.
    systemd.services.hermes-config-emit = lib.mkIf cfg.managedConfig {
      description = "Emit Nix-managed sections of hermes config.yaml";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      path = with pkgs; [(python3.withPackages (p: [p.pyyaml])) coreutils gnugrep];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        RemainAfterExit = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = ["/home/${cfg.user}/.hermes"];

        ExecStart = let
          managedProvidersJson = pkgs.writeText "hermes-managed-providers.json"
            (builtins.toJSON cfg.managedProviders);
          managedFallbackJson = pkgs.writeText "hermes-managed-fallback.json"
            (builtins.toJSON cfg.managedFallbackProviders);
        in pkgs.writeShellScript "hermes-config-emit" ''
          set -euo pipefail

          HERMES_CONFIG="/home/${cfg.user}/.hermes/config.yaml"

          if [ ! -f "$HERMES_CONFIG" ]; then
            echo "[hermes-config-emit] No config.yaml found at $HERMES_CONFIG"
            echo "[hermes-config-emit] Skipping — emit requires an existing hand-maintained file"
            exit 0
          fi

          # Managed sections: written verbatim into a temporary YAML file,
          # then merged into config.yaml via Python 3 ruamel.yaml if
          # available, falling back to dict-based overwrite otherwise.
          MANAGED_TMP=$(mktemp /tmp/hermes-managed-XXXXXX.yaml)
          trap 'rm -f "$MANAGED_TMP"' EXIT

          # Emit Nix-managed sections as a YAML document.
          # python3 + yaml is ALWAYS available on NixOS systems; if the
          # import fails (rare), we abort the boot unit so activation
          # fails loudly rather than silently corrupting the file.
          python3 - <<PYEOF > "$MANAGED_TMP"
import sys, json
try:
    import yaml
except ImportError:
    print("yaml module not available; aborting hermes-config-emit", file=sys.stderr)
    sys.exit(1)

with open("${managedProvidersJson}") as f:
    managed_providers = json.load(f)
with open("${managedFallbackJson}") as f:
    managed_fallback = json.load(f)

doc = {}
if managed_providers:
    doc["providers"] = managed_providers
if managed_fallback:
    doc["fallback_providers"] = managed_fallback

# Preserve discovered YAML semantics: only top-level keys that exist
# get overwritten. Empty defaults mean "leave existing config alone".
yaml.safe_dump(
    doc,
    stream=sys.stdout,
    sort_keys=False,
    default_flow_style=False,
    allow_unicode=True,
)
PYEOF

          # Merge in-place. python3 merges the managed keys over the
          # existing document, preserving all other top-level keys.
          MERGED_TMP=$(mktemp /tmp/hermes-emit-merged-XXXXXX.yaml)

          python3 - <<PYEOF
import sys, json, os
import yaml

with open("$HERMES_CONFIG") as f:
    existing = yaml.safe_load(f) or {}

with open("$MANAGED_TMP") as f:
    managed = yaml.safe_load(f) or {}

for k, v in managed.items():
    existing[k] = v

with open("$MERGED_TMP", "w") as f:
    yaml.safe_dump(existing, f, sort_keys=False, default_flow_style=False, allow_unicode=True)
PYEOF

          # Idempotency: compare hashes before swapping the live file.
          if cmp -s "$MERGED_TMP" "$HERMES_CONFIG"; then
            echo "[hermes-config-emit] config.yaml unchanged (managed sections already in sync)"
          else
            cp "$HERMES_CONFIG" "$HERMES_CONFIG.bak.$(date +%s)" 2>/dev/null || true
            mv "$MERGED_TMP" "$HERMES_CONFIG"
            echo "[hermes-config-emit] ✓ Wrote managed sections (backup kept with .bak.<unix-ts> suffix)"
          fi

          chown ${cfg.user}:users "$HERMES_CONFIG" 2>/dev/null || true
          chmod 600 "$HERMES_CONFIG" 2>/dev/null || true

          rm -f "$MANAGED_TMP" "$MERGED_TMP"
        '';
      };
    };
  };
}

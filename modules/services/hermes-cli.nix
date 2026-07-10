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
    for bin in ${hermesPkg}/bin/*; do
      name=$(basename "$bin")
      makeWrapper "$bin" "$out/bin/$name" \
        --prefix LD_LIBRARY_PATH : "${hermesAudioLibPath}"
    done
  '';

  # Expose the wrapped hermes bin dir so Home Manager (user-local symlink)
  # and other modules can reference it by store path without touching
  # /run/current-system at pure-eval time.
  wrappedBinPath = "${hermesPkgWrapped}/bin/hermes";

  # Use base hermes-agent package without WhatsApp bridge (stub removed)
  # WhatsApp functionality temporarily disabled

  # If hermes-agent is enabled, use its state dir. Otherwise, use user home.
  useAgentStateDir = hermesAgentCfg.enable or false;

  # Declarative MCP server configuration — sourced from mcp-server-registry
  # If registry is enabled, use its generated config; otherwise fall back to inline defaults
  registryCfg = config.services.mcp-servers or {};
  useRegistry = false; # Disabled until mcp-servers exports hermesMcpYaml

  # Inline fallback MCP servers (used when registry is not enabled)
  fallbackMcpServersBlock = pkgs.writeText "hermes-mcp-servers.yaml" ''
    mcp_servers:
      kubernetes:
        url: http://kubernetes-mcp.infra.svc.cluster.local:8080/mcp
        connect_timeout: 30
        timeout: 60
      lightpanda:
        command: lightpanda
        args:
          - mcp
        connect_timeout: 30
        timeout: 60
      nixos-cluster:
        command: nix
        args:
          - run
          - /etc/nixos#nixos-cluster-mcp
        connect_timeout: 30
        timeout: 60
      searxng:
        command: /data/agents/mcp-bridges/searxng-mcp.sh
        connect_timeout: 30
        timeout: 60
      selfhosted-tools:
        command: /data/agents/mcp-bridges/selfhosted-mcp.sh
        connect_timeout: 30
        timeout: 60
      github:
        command: /data/agents/mcp-bridges/github-mcp.sh
        connect_timeout: 30
        timeout: 120
      git:
        command: /data/agents/mcp-bridges/git-mcp.sh
        connect_timeout: 30
        timeout: 60
      casdoor:
        command: python3
        args:
          - /data/agents/mcp-bridges/casdoor-mcp-bridge.py
        connect_timeout: 30
        timeout: 60
        description: Casdoor SSO/OIDC - application management (5 tools, Bearer auth)
      context7:
        command: /data/agents/mcp-bridges/context7-mcp.sh
        connect_timeout: 30
        timeout: 60
      cua-driver:
        command: /data/agents/mcp-bridges/cua-driver-mcp.sh
        connect_timeout: 30
        timeout: 60
      yt-dlp:
        command: /data/agents/mcp-bridges/yt-dlp-mcp.sh
        connect_timeout: 15
        timeout: 300
        description: yt-dlp video/audio downloader — YouTube, X/Twitter, 1000+ sites (7 tools)
      maplespike:
        command: /data/agents/mcp-bridges/maplespike-mcp-std.sh
        connect_timeout: 30
        timeout: 120
        enabled: true
      agentmemory:
        command: /data/agents/mcp-bridges/agentmemory-mcp.sh
        connect_timeout: 30
        timeout: 120
        description: Agentmemory — 53 MCP tools for persistent coding memory
      graphiti:
        url: http://localhost:8000/mcp
        connect_timeout: 30
        timeout: 120
        description: Graphiti temporal knowledge graph MCP server
      sequential-thinking:
        command: /data/agents/mcp-bridges/sequential-thinking-mcp.sh
        connect_timeout: 30
        timeout: 60
        description: Sequential thinking — chain reasoning steps with continuity
  '';

  mcpServersBlock =
    if useRegistry
    then registryCfg.lib.mcp-registry.hermesMcpYaml
    else fallbackMcpServersBlock;

  # Python script to merge mcp_servers section into Hermes config.yaml
  # Uses line-by-line parsing to avoid regex escape issues with Nix multiline strings
  mcpMergeScript = pkgs.writeText "hermes-mcp-merge.py" (
    builtins.concatStringsSep "\n" [
      "import sys"
      "config_path = sys.argv[1]"
      "mcp_path = sys.argv[2]"
      "with open(config_path) as f:"
      "    lines = f.readlines()"
      "with open(mcp_path) as f:"
      "    mcp_block = f.read().strip()"
      "# Strip existing mcp_servers section"
      "in_mcp = False"
      "filtered = []"
      "for line in lines:"
      "    # Detect top-level mcp_servers: key (not indented)"
      "    if line.startswith('mcp_servers:') or line.startswith('mcp_servers: '):"
      "        in_mcp = True"
      "        continue"
      "    if in_mcp:"
      "        # Skip indented children (part of mcp_servers block)"
      "        if line.startswith(' ') or line.startswith(chr(9)) or line.strip() == '':"
      "            continue"
      "        # Non-indented, non-empty line = next top-level section"
      "        in_mcp = False"
      "    filtered.append(line)"
      "content = ''.join(filtered).rstrip()"
      "# Insert new block before smart_model_routing or at end"
      "marker = 'smart_model_routing:'"
      "full = content.split(marker, 1)"
      "if len(full) == 2:"
      "    result = full[0] + mcp_block + chr(10) + chr(10) + marker + full[1]"
      "else:"
      "    result = content + chr(10) + chr(10) + mcp_block + chr(10)"
      "with open(config_path, 'w') as f:"
      "    f.write(result)"
    ]
  );
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
      description = "Path to sops-nix secret file containing ZAI_API_KEY";
      example = "config.age.secrets.zai-api-key.path";
    };

    nvidiaApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to sops-nix secret file containing NVIDIA_API_KEY";
      example = "config.age.secrets.nvidia-api-key.path";
    };

    casdoorJwtFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to sops-nix secret file containing Casdoor JWT for MCP";
      example = "config.age.secrets.casdoor-hermes-jwt.path";
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
            model = "nemotron-3-ultra-free";
          };
        }
      '';
      description = "Provider definitions mirroring the `providers:` block in hermes config.yaml";
    };

    managedFallbackProviders = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ''["opencode-zen" "opencode-go" "zai" "nvidia"]'';
      description = "Ordered list of fallback providers matching `fallback_providers:` in hermes config.yaml";
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
    systemd.services.hermes-config-secrets = lib.mkIf (cfg.casdoorJwtFile != null) {
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

          # Wait for sops-nix secret
          for i in $(seq 1 30); do
            if [ -f "${cfg.casdoorJwtFile}" ] && [ -s "${cfg.casdoorJwtFile}" ]; then
              break
            fi
            sleep 1
          done

          if [ ! -f "${cfg.casdoorJwtFile}" ] || [ ! -s "${cfg.casdoorJwtFile}" ]; then
            echo "[hermes-config] WARNING: Casdoor JWT not available"
            exit 0
          fi

          JWT=$(cat "${cfg.casdoorJwtFile}")

          # Inject Casdoor JWT into MCP server config
          if grep -q 'casdoor:' "$HERMES_CONFIG"; then
            sed -i "/^[[:space:]]*casdoor:/,/^[[:space:]]*\(connect_timeout\|timeout\|command\|url\):/{
              s|Authorization: Bearer .*|Authorization: Bearer $JWT|
            }" "$HERMES_CONFIG"
            echo "[hermes-config] ✓ Injected Casdoor JWT"
          fi

          # Ensure all base_url entries point to gateway (prevents stale IPs)
          GATEWAY_URL="${cfg.gatewayUrl}"
          # Fix any remaining direct Sentry or stale pod IPs
          sed -i "s|base_url: http://10\.1\.1\.140:1235/v1|base_url: $GATEWAY_URL|g" "$HERMES_CONFIG"
          sed -i "s|base_url: http://10\.4\.[0-9]*\.[0-9]*:1235/v1|base_url: $GATEWAY_URL|g" "$HERMES_CONFIG"
          # Fix any corrupted [IP_ADDRESS] placeholders from previous sed failures
          sed -i "s|base_url: http://\[IP_ADDRESS\]:8080/v1|base_url: $GATEWAY_URL|g" "$HERMES_CONFIG"

          # Enforce Z.AI coding plan endpoint (not pay-as-you-go /api/paas/v4)
          sed -i "s|base_url: https://api\.z\.ai/api/paas/v4[^/]|base_url: https://api.z.ai/api/coding/paas/v4|g" "$HERMES_CONFIG"
          # Also catch the exact pay-as-you-go path without trailing chars
          sed -i "s|base_url: https://api\.z\.ai/api/paas/v4$|base_url: https://api.z.ai/api/coding/paas/v4|g" "$HERMES_CONFIG"

          chown ${cfg.user}:users "$HERMES_CONFIG" 2>/dev/null || true
          chmod 600 "$HERMES_CONFIG" 2>/dev/null || true

          echo "[hermes-config] Done"
        '';
      };
    };

    # ── Declarative MCP server management ─────────────────────────
    # Merges Nix-defined mcp_servers into Hermes config.yaml at boot.
    # API keys are injected from sops-nix secrets (ZAI_API_KEY).
    systemd.services.hermes-mcp-servers = {
      restartIfChanged = true;
      description = "Inject declarative MCP servers into Hermes config";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      path = with pkgs; [python3 coreutils gnused];

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

            # Wait for ZAI API key
            ${lib.optionalString (cfg.apiKeyFile != null) ''
              for i in $(seq 1 30); do
                if [ -f "${cfg.apiKeyFile}" ] && [ -s "${cfg.apiKeyFile}" ]; then
                  break
                fi
                sleep 1
              done
            ''}

            # Build mcp_servers block with injected API key.
            # 2026-07-03: explicitly check that the path resolves to a real file
            # before running cat. Two failure modes we tolerate:
            #   1) cfg.apiKeyFile == null (option unset) → empty ZAI_KEY.
            #   2) cfg.apiKeyFile set but sops-nix didn't provision the file
            #      on this host → also empty ZAI_KEY.
            # Empty (rather than the literal string "missing") so the `sed`
            # below substitutes `__ZAI_API_KEY__` with "" — downstream
            # MCP consumers treat an empty bearer as "no auth provided",
            # which is the truthful signal here. The literal "missing"
            # would have rendered as the bearer token, causing
            # confusing client-side 401s instead of a clean absence.
            # The other half of the original bug is `set -euo pipefail`:
            # `cat` on a missing file returns 1, command substitution
            # surfaces that, and the script aborts — which is the
            # 30 s then status=1/FAILURE pattern.
            ZAI_KEY="$(if [ -n "${cfg.apiKeyFile}" ] && [ -e "${cfg.apiKeyFile}" ]; then cat "${cfg.apiKeyFile}" 2>/dev/null; else echo; fi)"
            MCP_TMP=$(mktemp /tmp/hermes-mcp-XXXXXX.yaml)
            sed "s/__ZAI_API_KEY__/$ZAI_KEY/g" ${mcpServersBlock} > "$MCP_TMP"

            # Merge into config.yaml using Python3
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

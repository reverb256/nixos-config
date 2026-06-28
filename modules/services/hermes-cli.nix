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

      # Patch cua-driver backend: allow Linux (0.6.8+ Wayland) and handle
      # windows with pid=None (cursor overlays) that crash int(None).
      if [ -f "$SITE_PKGS/tools/computer_use/cua_backend.py" ]; then
        patch -p1 -d "$(dirname "$SITE_PKGS/tools/computer_use/cua_backend.py")" < ${./../../patches/hermes-cua-backend-linux.patch}
      fi

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
      description = "Path to agenix secret file containing ZAI_API_KEY";
      example = "config.age.secrets.zai-api-key.path";
    };

    nvidiaApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to agenix secret file containing NVIDIA_API_KEY";
      example = "config.age.secrets.nvidia-api-key.path";
    };

    casdoorJwtFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to agenix secret file containing Casdoor JWT for MCP";
      example = "config.age.secrets.casdoor-hermes-jwt.path";
    };

    opencodeGoApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to agenix secret file containing OpenCode Go API key";
      example = "config.age.secrets.opencode-go-api-key.path";
    };

    opencodeZenApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to agenix secret file containing OpenCode Zen API key";
      example = "config.age.secrets.opencode-api-key.path";
    };

    kilocodeApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to agenix secret file containing Kilo Code API key";
      example = "config.age.secrets.kilo-api-key.path";
    };

    geminiApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to agenix secret file containing Gemini API key";
      example = "config.age.secrets.gemini-api-key.path";
    };

    hfTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to agenix secret file containing HuggingFace token";
      example = "config.age.secrets.huggingface-token.path";
    };

    githubTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to agenix secret file containing GitHub token";
      example = "config.age.secrets.github-token.path";
    };

    gatewayUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${config.networking.cluster.hosts.zephyr.ip}:${toString config.networking.cluster.kubernetes.nodePorts.ai-inference-gateway}/v1";
      description = "AI Inference Gateway URL for routing";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install hermes package system-wide
    environment.systemPackages = [hermesPkg pkgs.portaudio];

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

    # Inject agenix secrets into Hermes config at boot
    systemd.services.hermes-config-secrets = lib.mkIf (cfg.casdoorJwtFile != null) {
      description = "Inject agenix secrets into Hermes config";
      after = ["agenix.service" "network.target"];
      wants = ["agenix.service"];
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

          # Wait for agenix secret
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
    # API keys are injected from agenix secrets (ZAI_API_KEY).
    systemd.services.hermes-mcp-servers = {
      restartIfChanged = true;
      description = "Inject declarative MCP servers into Hermes config";
      after = ["agenix.service" "network.target"];
      wants = ["agenix.service"];
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

            # Build mcp_servers block with injected API key
            ZAI_KEY="$(if [ -n "${cfg.apiKeyFile}" ]; then cat "${cfg.apiKeyFile}" 2>/dev/null; else echo missing; fi)"
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
  };
}

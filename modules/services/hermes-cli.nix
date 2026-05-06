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
  hermesPkg = inputs.hermes-agent.packages.${pkgs.system}.default;

  # Build the WhatsApp bridge from the hermes-agent source
  # The upstream Nix package omits scripts/whatsapp-bridge/ — this fills the gap.
  whatsapp-bridge = pkgs.callPackage ../../packages/hermes-whatsapp-bridge.nix {
    hermesSrc = inputs.hermes-agent;
  };

  # Wrap hermes-agent with WhatsApp bridge injected into site-packages/
  # This makes both `hermes whatsapp` (CLI pairing) and the gateway adapter work.
  hermes-with-whatsapp = pkgs.callPackage ../../packages/hermes-with-whatsapp.nix {
    inherit lib;
    hermes-pkg = hermesPkg;
    inherit whatsapp-bridge;
  };

  # If hermes-agent is enabled, use its state dir. Otherwise, use user home.
  useAgentStateDir = hermesAgentCfg.enable or false;

  # Declarative MCP server configuration for Hermes
  # API keys are injected at runtime via __PLACEHOLDER__ tokens
  mcpServersBlock = pkgs.writeText "hermes-mcp-servers.yaml" ''
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
      web-reader:
        url: https://api.z.ai/api/mcp/web_reader/mcp
        headers:
          Authorization: Bearer __ZAI_API_KEY__
        timeout: 60
      web-search:
        url: https://api.z.ai/api/mcp/web_search_prime/mcp
        headers:
          Authorization: Bearer __ZAI_API_KEY__
        timeout: 60
      zread:
        url: https://api.z.ai/api/mcp/zread/mcp
        headers:
          Authorization: Bearer __ZAI_API_KEY__
        timeout: 60
      casdoor:
        command: python3
        args:
          - /data/agents/mcp-bridges/casdoor-mcp-bridge.py
        connect_timeout: 30
        timeout: 60
        description: Casdoor SSO/OIDC - application management (5 tools, Bearer auth)
  '';

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

    openrouterApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to agenix secret file containing OPENROUTER_API_KEY";
      example = "config.age.secrets.openrouter-api-key.path";
    };

    casdoorJwtFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to agenix secret file containing Casdoor JWT for MCP";
      example = "config.age.secrets.casdoor-hermes-jwt.path";
    };

    gatewayUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${config.networking.cluster.hosts.zephyr.ip}:${toString config.networking.cluster.kubernetes.nodePorts.ai-gateway}/v1";
      description = "AI Inference Gateway URL for routing";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install hermes package system-wide
    environment.systemPackages = [hermes-with-whatsapp];

    # Only set HERMES_HOME if hermes-agent is NOT managing it
    # The hermes-agent module sets addToSystemPackages which also sets HERMES_HOME
    environment.variables.HERMES_HOME = lib.mkIf (!useAgentStateDir) "/home/${cfg.user}/.hermes";

    # Create hermes state directory with proper config (only if not using agent state)
    system.activationScripts.hermes-cli-setup = lib.mkIf (!useAgentStateDir) (
      lib.stringAfter ["users"] ''
              HERMES_HOME="/home/${cfg.user}/.hermes"

              # Create directory structure
              mkdir -p "$HERMES_HOME"/{sessions,memories,skills,cron,logs}

              # Write config.yaml if it doesn't exist or is managed by us
              if [ ! -f "$HERMES_HOME/config.yaml" ] || grep -q "# Managed by NixOS" "$HERMES_HOME/config.yaml" 2>/dev/null; then
                cat > "$HERMES_HOME/config.yaml" << YAML_EOF
        # Managed by NixOS - hermes-cli module
        # All inference routed through AI Inference Gateway
        model:
          provider: ai-gateway
          base_url: http://${config.networking.cluster.hosts.zephyr.ip}:${toString config.networking.cluster.kubernetes.nodePorts.ai-gateway}/v1
          default: qwen/qwen3-coder-480b-a35b-instruct
          api_key: none

        providers:
          ai-gateway:
            base_url: http://${config.networking.cluster.hosts.zephyr.ip}:${toString config.networking.cluster.kubernetes.nodePorts.ai-gateway}/v1
            api_key: none
          zai:
            base_url: https://api.z.ai/api/coding/paas/v4
            api_key_env: ZAI_API_KEY
          nvidia-nim:
            base_url: https://integrate.api.nvidia.com/v1
            api_key_env: NVIDIA_API_KEY
          llama-cpp-zephyr:
            base_url: http://llama-server-zephyr.ai-inference.svc.cluster.local:1235/v1
            api_key: unused
          llama-cpp-sentry:
            base_url: http://llama-server-sentry.ai-inference.svc.cluster.local:1235/v1
            api_key: unused

        fallback_providers:
          - ai-gateway
          - zai
          - nvidia-nim
          - llama-cpp-zephyr
          - llama-cpp-sentry

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

        # WhatsApp bridge — point to Nix-built bridge since upstream
        # package omits scripts/whatsapp-bridge/
        platforms:
          whatsapp:
            extra:
              bridge_script: ${whatsapp-bridge}/bridge.js
        YAML_EOF
                chmod 644 "$HERMES_HOME/config.yaml"
              fi

              # Write .env with API keys from agenix secrets
              # This runs unconditionally — .env must always reflect current secrets
              echo "# Hermes environment variables" > "$HERMES_HOME/.env"
              ${lib.optionalString (cfg.apiKeyFile != null) ''
          if [ -f "${cfg.apiKeyFile}" ]; then
            echo -n "ZAI_API_KEY=" >> "$HERMES_HOME/.env"
            cat "${cfg.apiKeyFile}" >> "$HERMES_HOME/.env"
            echo "" >> "$HERMES_HOME/.env"
          fi
        ''}
              ${lib.optionalString (cfg.nvidiaApiKeyFile != null) ''
          if [ -f "${cfg.nvidiaApiKeyFile}" ]; then
            echo -n "NVIDIA_API_KEY=" >> "$HERMES_HOME/.env"
            cat "${cfg.nvidiaApiKeyFile}" >> "$HERMES_HOME/.env"
            echo "" >> "$HERMES_HOME/.env"
          fi
        ''}
              ${lib.optionalString (cfg.openrouterApiKeyFile != null) ''
          if [ -f "${cfg.openrouterApiKeyFile}" ]; then
            echo -n "OPENROUTER_API_KEY=" >> "$HERMES_HOME/.env"
            cat "${cfg.openrouterApiKeyFile}" >> "$HERMES_HOME/.env"
            echo "" >> "$HERMES_HOME/.env"
          fi
        ''}
              chmod 600 "$HERMES_HOME/.env"

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
        hermes completion fish 2>/dev/null | source
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

          HERMES_CONFIG="/home/${cfg.user}/.hermes/config.yaml"

          if [ ! -f "$HERMES_CONFIG" ]; then
            echo "[hermes-mcp] No config.yaml found, skipping"
            exit 0
          fi

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

          echo "[hermes-mcp] ✓ MCP servers configured"
        '';
      };
    };
  };
}

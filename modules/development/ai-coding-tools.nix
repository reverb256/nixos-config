{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.ai-coding-tools;
  inherit
    (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    optionalString
    ;

  mcpDefs = import ./ai-coding-tools/mcp-defs.nix {inherit lib;};

  # Gateway URL from network-constants (single source of truth)
  # Use nodePort for host tools (ClusterIP only accessible from within K8s)
  gatewayUrl = "http://${config.networking.cluster.hosts.zephyr.ip}:${toString config.networking.cluster.kubernetes.nodePorts.ai-inference-gateway}";

  droidGen = import ./ai-coding-tools/droid.nix {
    inherit cfg pkgs gatewayUrl;
    inherit (mcpDefs) mkMcpServersJson;
  };
  claudeGen = import ./ai-coding-tools/claude.nix {
    inherit cfg pkgs gatewayUrl;
    inherit (mcpDefs) mkMcpServersJson;
  };
  crushGen = import ./ai-coding-tools/crush.nix {
    inherit cfg pkgs gatewayUrl;
    inherit (mcpDefs) mkMcpServersJson;
  };
  opencodeGen = import ./ai-coding-tools/opencode.nix {
    inherit cfg pkgs gatewayUrl;
    inherit (mcpDefs) mkMcpServersJson;
  };
  piGen = import ./ai-coding-tools/pi.nix {
    inherit cfg pkgs gatewayUrl;
    inherit (mcpDefs) mkMcpServersJson;
  };
  ompGen = import ./ai-coding-tools/omp.nix {
    inherit cfg pkgs gatewayUrl;
    inherit (mcpDefs) mkMcpServersJson;
  };
in {
  options.services.ai-coding-tools = {
    enable = mkEnableOption "Harmonized MCP configuration for all AI coding tools (Droid, Claude Code, Crush, OpenCode)";
    user = mkOption {
      type = types.str;
      default = "j_kro";
      description = "User for AI coding tool configs";
    };
    zaiApiKeyFile = mkOption {
      type = types.path;
      default = "/run/agenix/zai-api-key";
      description = "Path to Z.AI API key (agenix secret)";
    };
    context7ApiKeyFile = mkOption {
      type = types.path;
      default = "/run/agenix/context7-api-key";
      description = "Path to Context7 API key (agenix secret)";
    };
    nvidiaNimApiKeyFile = mkOption {
      type = types.path;
      default = "/run/agenix/nvidia-api-key";
      description = "Path to NVIDIA NIM API key (agenix secret)";
    };
    opencodeGoApiKeyFile = mkOption {
      type = types.path;
      default = "/run/agenix/opencode-go-api-key";
      description = "Path to OpenCode Go API key (agenix secret)";
    };
    tools = {
      droid = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Generate Factory Droid MCP config (~/.factory/mcp.json)";
        };
      };
      claude = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Generate Claude Code MCP config (~/.config/claude/mcp.json)";
        };
      };
      crush = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Generate Crush MCP config (~/.config/crush/crush.json)";
        };
      };
      opencode = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Generate OpenCode config with MCP servers (~/.opencode/config.json)";
        };
      };
      pi = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Generate Pi agent config (~/.pi/agent/)";
        };
      };
      omp = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Generate OMP agent config (~/.omp/agent/)";
        };
      };
    };
    enableShellEnv = mkOption {
      type = types.bool;
      default = true;
      description = "Set ZAI_API_KEY and related env vars in shell session";
    };
  };
  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /home/${cfg.user}/.factory 0700 ${cfg.user} users -"
      "d /home/${cfg.user}/.config/claude 0755 ${cfg.user} users -"
      "d /home/${cfg.user}/.config/crush 0755 ${cfg.user} users -"
      "d /home/${cfg.user}/.config/crush/commands 0755 ${cfg.user} users -"
      "d /home/${cfg.user}/.opencode 0755 ${cfg.user} users -"
      "d /home/${cfg.user}/.pi/agent 0755 ${cfg.user} users -"
      "d /home/${cfg.user}/.omp/agent 0755 ${cfg.user} users -"
    ];
    environment.sessionVariables = mkIf cfg.enableShellEnv {
      ZAI_API_KEY_FILE = cfg.zaiApiKeyFile;
      CONTEXT7_API_KEY_FILE = cfg.context7ApiKeyFile;
    };
    systemd.services.ai-coding-tools-config = {
      description = "Generate harmonized MCP configs for AI coding tools";
      after = [
        "agenix.service"
        "network.target"
      ];
      wants = ["agenix.service"];
      wantedBy = ["multi-user.target"];
      path = [
        pkgs.jq
        pkgs.coreutils
        pkgs.gnugrep
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        RemainAfterExit = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "no";
        ReadWritePaths = [
          "/home/${cfg.user}/.factory"
          "/home/${cfg.user}/.config/claude"
          "/home/${cfg.user}/.config/crush"
          "/home/${cfg.user}/.opencode"
          "/home/${cfg.user}/.pi"
          "/home/${cfg.user}/.omp"
        ];
        ExecStart = pkgs.writeShellScript "ai-coding-tools-generate" ''
          set -euo pipefail
          for secret in ${cfg.zaiApiKeyFile} ${cfg.context7ApiKeyFile} ${cfg.nvidiaNimApiKeyFile} ${cfg.opencodeGoApiKeyFile}; do
            for i in {1..30}; do
              if [ -f "$secret" ] && [ -s "$secret" ]; then
                break
              fi
              if [ "$i" -eq 30 ]; then
                echo "[ai-coding-tools] WARNING: Secret not available: $secret"
              fi
              sleep 1
            done
          done
          export ZAI_KEY_PATH="${cfg.zaiApiKeyFile}"
          ZAI_API_KEY="$(cat $ZAI_KEY_PATH 2>/dev/null || echo)"
          export CTX7_KEY_PATH="${cfg.context7ApiKeyFile}"
          CONTEXT7_API_KEY="$(cat $CTX7_KEY_PATH 2>/dev/null || echo)"
          export NVIDIA_NIM_KEY_PATH="${cfg.nvidiaNimApiKeyFile}"
          NVIDIA_NIM_API_KEY="$(cat $NVIDIA_NIM_KEY_PATH 2>/dev/null || echo)"
          export OPENCODE_GO_KEY_PATH="${cfg.opencodeGoApiKeyFile}"
          OPENCODE_GO_API_KEY="$(cat $OPENCODE_GO_KEY_PATH 2>/dev/null || echo)"
          echo "[ai-coding-tools] Generating harmonized MCP configs..."
          ${optionalString cfg.tools.droid.enable ''
            echo "[ai-coding-tools] Generating Droid settings..."
            ${droidGen.mkDroidSettings}
            echo "[ai-coding-tools] Generating Droid MCP config..."
            ${droidGen.mkDroidMcpJson}
          ''}
          ${optionalString cfg.tools.claude.enable ''
            echo "[ai-coding-tools] Generating Claude Code config..."
            ${claudeGen.mkClaudeMcpJson}
          ''}
          ${optionalString cfg.tools.crush.enable ''
            echo "[ai-coding-tools] Generating Crush config..."
            ${crushGen.mkCrushConfig}
          ''}
          ${optionalString cfg.tools.opencode.enable ''
            echo "[ai-coding-tools] Generating OpenCode config..."
            ${opencodeGen.mkOpencodeConfig}
          ''}
          ${optionalString cfg.tools.pi.enable ''
            echo "[ai-coding-tools] Generating Pi config..."
            ${piGen.mkPiConfig}
          ''}
          ${optionalString cfg.tools.omp.enable ''
            echo "[ai-coding-tools] Generating OMP config..."
            ${ompGen.mkOmpConfig}
          ''}
          echo "[ai-coding-tools] All configs generated successfully"
        '';
      };
    };
    programs.fish.interactiveShellInit = mkIf cfg.enableShellEnv ''
      if test -f ${cfg.zaiApiKeyFile}
        set -gx ZAI_API_KEY (cat ${cfg.zaiApiKeyFile})
      end
      if test -f ${cfg.context7ApiKeyFile}
        set -gx CONTEXT7_API_KEY (cat ${cfg.context7ApiKeyFile})
      end
    '';
    programs.bash.interactiveShellInit = mkIf cfg.enableShellEnv ''
      if [ -f ${cfg.zaiApiKeyFile} ]; then
        ZAI_KEY_PATH="${cfg.zaiApiKeyFile}"
        export ZAI_API_KEY="$(cat $ZAI_KEY_PATH)"
      fi
      if [ -f ${cfg.context7ApiKeyFile} ]; then
        CTX7_KEY_PATH="${cfg.context7ApiKeyFile}"
        export CONTEXT7_API_KEY="$(cat $CTX7_KEY_PATH)"
      fi
    '';
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "crush" ''
        export PATH="${pkgs.nodejs_22}/bin:$PATH"
        export npm_config_cache="/var/cache/ai-inference/npm"
        exec ${pkgs.nodejs_22}/bin/npx -y @charmland/crush@latest "$@"
      '')
      (pkgs.writeShellScriptBin "ai-tools-regenerate" ''
        echo "Regenerating all AI coding tool MCP configs..."
        sudo systemctl restart ai-coding-tools-config.service
        journalctl -u ai-coding-tools-config.service -n 20 --no-pager
      '')
      (pkgs.writeShellScriptBin "ai-tools-status" ''
        echo "=== AI Coding Tools Status ==="
        echo ""
        echo "Config files:"
        for f in \
          "/home/${cfg.user}/.factory/mcp.json" \
          "/home/${cfg.user}/.config/claude/mcp.json" \
          "/home/${cfg.user}/.config/crush/crush.json" \
          "/home/${cfg.user}/.opencode/config.json"           "/home/${cfg.user}/.pi/agent/mcp.json"           "/home/${cfg.user}/.omp/agent/mcp.json"
        do
          if [ -f "$f" ]; then
            servers=$(${pkgs.jq}/bin/jq -r '[.mcpServers // .mcp | keys[]] | length' "$f" 2>/dev/null || echo "?")
            echo "  ✓ $f ($servers MCP servers)"
          else
            echo "  ✗ $f (missing)"
          fi
        done
        echo ""
        echo "Secrets:"
        for s in ${cfg.zaiApiKeyFile} ${cfg.context7ApiKeyFile}; do
          if [ -f "$s" ] && [ -s "$s" ]; then
            echo "  ✓ $s"
          else
            echo "  ✗ $s (missing)"
          fi
        done
        echo ""
        echo "MCP wrapper commands:"
        for cmd in mcp-filesystem mcp-git mcp-fetch mcp-playwright mcp-lightpanda mcp-context7 mcp-gateway-bridge; do
          if command -v "$cmd" &>/dev/null; then
            echo "  ✓ $cmd"
          else
            echo "  ✗ $cmd (not in PATH)"
          fi
        done
      '')
    ];
    environment.etc."ai-coding-tools/README.md".text = ''
      Managed by: `services.ai-coding-tools` NixOS module
      Regenerate: `ai-tools-regenerate`
      Status:     `ai-tools-status`
      | Provider | Endpoint | Key Source | Tools |
      |----------|----------|------------|-------|
      | Z.AI (Anthropic) | api.z.ai/api/anthropic | agenix | Droid |
      | Z.AI (OpenAI) | api.z.ai/api/coding/paas/v4 | agenix | OpenCode, Crush |
      | K8s AI Gateway | ai-inference-gateway:8080/v1 | None (internal) | OpenCode, Crush, Droid |
      | NVIDIA NIM | integrate.api.nvidia.com/v1 | agenix | OpenCode, Crush, Droid |
      | LM Studio | 127.0.0.1:1234/v1 | None (local) | OpenCode, Crush |
      | llama.cpp | 127.0.0.1:1235/v1 | None (local) | OpenCode |
      | Server | Type | Purpose | All Tools |
      |--------|------|---------|-----------|
      | zai-mcp-server | stdio | Z.AI image/video/analysis | Yes |
      | web-search-prime | HTTP | Z.AI web search | Yes |
      | web-reader | HTTP | Z.AI URL reader | Yes |
      | zread | HTTP | Z.AI GitHub repo reader | Yes |
      | filesystem | stdio | Local filesystem access | Yes |
      | git | stdio | Git operations | Yes |
      | fetch | stdio | Web fetching | Yes |
      | playwright | stdio | Browser automation | Yes |
      | context7 | stdio | Documentation search | Yes |
      | chrome-devtools | stdio | Chrome debugging | Yes |
      | gateway | stdio | AI Inference Gateway bridge | Yes |
      | nixos | stdio | NixOS helper (uvx) | Claude only |
      | Tool | Config Path | Format |
      |------|------------|--------|
      | Droid (Factory) | ~/.factory/mcp.json | MCP servers only |
      | Claude Code | ~/.config/claude/mcp.json | MCP servers only |
      | Crush | ~/.config/crush/crush.json | Provider + MCP |
      | OpenCode | ~/.opencode/config.json | Provider + MCP |
      | Tool | Command | Source |
      |------|---------|--------|
      | Crush | `crush` | npx @charmland/crush@latest |
      All keys managed via agenix secrets:
      - zai-api-key → /run/agenix/zai-api-key
      - context7-api-key → /run/agenix/context7-api-key
      - nvidia-api-key → /run/agenix/nvidia-api-key
      Keys are loaded into shell environment (fish/bash) and referenced
      in configs at generation time. Z.AI HTTP servers use Bearer tokens.
    '';
  };
}

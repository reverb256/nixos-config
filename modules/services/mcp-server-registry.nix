# MCP Server Registry — Single Source of Truth
#
# Defines all MCP servers in one place and generates configs for:
#   C2: Claude Code settings.json (mcpServers)
#   C3: Hermes config.yaml (mcp_servers)
#   C4: Kagent RemoteMCPServer CRDs
#   C4: NetworkPolicy per server
#   C5: Casdoor gateway registration
#
# Usage:
#   services.mcp-registry.enable = true;
#   services.mcp-registry.generateClaudeCode = true;
#   services.mcp-registry.generateHermes = true;
#   services.mcp-registry.generateKagentCRDs = true;
#   services.mcp-registry.generateNetworkPolicies = true;
#   services.mcp-registry.generateCasdoorApps = true;
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.mcp-registry;
  inherit (lib) mkEnableOption mkOption types mkIf;

  # ── MCP Server Definitions ──────────────────────────────────────────────
  # Each server: { type, transport, command, args, env, url, headers, ... }
  #
  # Transport: "stdio" | "sse" | "http"
  # Scope: "local" (host) | "cluster" (K8s) | "remote" (external HTTP)
  #
  # C1: nixos-cluster-mcp canonical definition — packages/nixos-cluster-mcp/
  #     is the canonical source. /data/projects/own/nixos-cluster-mcp/ is removed.
  defaultServers = {
    # ── Local stdio servers (host-level) ────────────────────────────────
    github = {
      type = "stdio";
      scope = "local";
      command = "/data/agents/mcp-bridges/github-mcp.sh";
      description = "GitHub repositories, issues, PRs, actions (39 tools)";
      connectTimeout = 60;
      timeout = 120;
      casdoorApp = "app-github";
    };

    git = {
      type = "stdio";
      scope = "local";
      command = "/data/agents/mcp-bridges/git-mcp.sh";
      description = "Git operations (29 tools)";
      connectTimeout = 30;
      timeout = 60;
      casdoorApp = null;
    };

    searxng = {
      type = "stdio";
      scope = "local";
      command = "/data/agents/mcp-bridges/searxng-mcp.sh";
      description = "SearXNG web search (15 tools)";
      connectTimeout = 60;
      timeout = 90;
      casdoorApp = "app-searxng";
      ssePort = 9001;
    };

    selfhosted-tools = {
      type = "stdio";
      scope = "local";
      command = "/data/agents/mcp-bridges/selfhosted-mcp.sh";
      description = "Self-hosted tools (15 tools: web_reader, github file read, etc.)";
      connectTimeout = 60;
      timeout = 90;
      casdoorApp = null;
    };

    sequential-thinking = {
      type = "stdio";
      scope = "local";
      command = "/data/agents/mcp-bridges/sequential-thinking.sh";
      description = "Sequential thinking tool for complex reasoning";
      connectTimeout = 30;
      timeout = 60;
      casdoorApp = null;
    };

    # ── NixOS cluster MCP (C1: canonical — packages/nixos-cluster-mcp) ──
    nixos-cluster = {
      type = "stdio";
      scope = "local";
      command = "nix";
      args = ["run" "/etc/nixos#nixos-cluster-mcp"];
      description = "NixOS cluster management (15 tools: cluster_status, node_info, gpu_inventory, etc.)";
      connectTimeout = 30;
      timeout = 60;
      casdoorApp = "app-nixos-cluster";
      ssePort = 9004;
      package = "nixos-cluster-mcp";
    };

    casdoor = {
      type = "stdio";
      scope = "local";
      command = "python3";
      args = ["/data/agents/mcp-bridges/casdoor-mcp-bridge.py"];
      description = "Casdoor SSO/OIDC - application management (5 tools, Bearer auth)";
      connectTimeout = 30;
      timeout = 60;
      casdoorApp = null;
      ssePort = 9005;
    };

    # ── Cluster SSE servers (K8s) ───────────────────────────────────────
    kubernetes = {
      type = "sse";
      scope = "cluster";
      url = "http://kubernetes-mcp.infra.svc.cluster.local:8080/mcp";
      description = "Kubernetes cluster management (14 tools: pods, events, resources)";
      connectTimeout = 30;
      timeout = 60;
      casdoorApp = "app-kubernetes";
      namespace = "infra";
      ssePort = 8080;
    };

    # ── Remote HTTP servers (Z.AI) ──────────────────────────────────────
    web-search-prime = {
      type = "http";
      scope = "remote";
      url = "https://api.z.ai/api/mcp/web_search_prime/mcp";
      headers.Authorization = "Bearer $ZAI_API_KEY";
      description = "Z.AI web search prime";
      connectTimeout = 30;
      timeout = 60;
      casdoorApp = null;
    };

    web-reader = {
      type = "http";
      scope = "remote";
      url = "https://api.z.ai/api/mcp/web_reader/mcp";
      headers.Authorization = "Bearer $ZAI_API_KEY";
      description = "Z.AI web reader";
      connectTimeout = 30;
      timeout = 60;
      casdoorApp = null;
    };

    zread = {
      type = "http";
      scope = "remote";
      url = "https://api.z.ai/api/mcp/zread/mcp";
      headers.Authorization = "Bearer $ZAI_API_KEY";
      description = "Z.AI zread";
      connectTimeout = 30;
      timeout = 60;
      casdoorApp = null;
    };

    # ── Additional stdio servers ────────────────────────────────────────
    lightpanda = {
      type = "stdio";
      scope = "local";
      command = "/home/j_kro/.local/bin/lightpanda";
      args = ["mcp"];
      description = "Lightpanda web browser automation";
      connectTimeout = 30;
      timeout = 60;
      casdoorApp = null;
      ssePort = 9003;
    };

    filesystem = {
      type = "stdio";
      scope = "local";
      command = "mcp-filesystem";
      args = ["/etc/nixos" "/home/j_kro"];
      description = "Filesystem access (read/write, deferred tools)";
      connectTimeout = 30;
      timeout = 60;
      casdoorApp = null;
    };

    context7 = {
      type = "stdio";
      scope = "local";
      command = "mcp-context7";
      env.CONTEXT7_API_KEY = "$CONTEXT7_API_KEY";
      description = "Context7 documentation search";
      connectTimeout = 30;
      timeout = 60;
      casdoorApp = null;
    };

    chrome-devtools = {
      type = "stdio";
      scope = "local";
      command = "npx";
      args = ["-y" "chrome-devtools-mcp@latest"];
      description = "Chrome DevTools (deferred tools)";
      connectTimeout = 30;
      timeout = 60;
      casdoorApp = null;
    };

    playwright = {
      type = "stdio";
      scope = "local";
      command = "npx";
      args = ["-y" "@anthropic-ai/playwright-mcp@latest"];
      description = "Playwright browser automation (deferred tools)";
      connectTimeout = 30;
      timeout = 60;
      casdoorApp = null;
    };
  };

  # Merge default servers with user-provided extra servers
  allServers = cfg.defaultServers // cfg.extraServers;

  # Filter servers by scope
  stdioServers = lib.filterAttrs (_: s: s.type == "stdio") allServers;
  sseServers = lib.filterAttrs (_: s: s.type == "sse") allServers;
  httpServers = lib.filterAttrs (_: s: s.type == "http") allServers;
  localServers = lib.filterAttrs (_: s: s.scope == "local") allServers;
  clusterServers = lib.filterAttrs (_: s: s.scope == "cluster") allServers;

  # ── C2: Generate Claude Code settings.json mcpServers ───────────────────
  # Use builtins.toJSON for proper JSON escaping (control chars, quotes, etc.)
  mkClaudeCodeMcpServers = servers:
    builtins.toJSON {
      mcpServers = lib.mapAttrs (
        name: server: lib.filterAttrs (_: v: v != null && v != []) {
          command = server.command or null;
          args = if builtins.hasAttr "args" server then server.args else null;
          env = if builtins.hasAttr "env" server then server.env else null;
        }
      ) servers;
    };

  claudeCodeJson = pkgs.writeText "claude-code-mcp-servers.json"
    (mkClaudeCodeMcpServers stdioServers);

  # ── C3: Generate Hermes config.yaml mcp_servers ─────────────────────────
  mkHermesMcpServers = servers: let
    mkServerBlock = name: server: let
      lines = ["    ${name}:"];
      addLine = line: lines ++ [line];
    in
      lib.concatStringsSep "\n" (
        if server.type == "sse"
        then
          addLine "      url: ${server.url}"
          ++ addLine "      connect_timeout: ${toString (server.connectTimeout or 30)}"
          ++ addLine "      timeout: ${toString (server.timeout or 60)}"
        else if server.type == "http"
        then
          addLine "      url: ${server.url}"
          ++ addLine "      connect_timeout: ${toString (server.connectTimeout or 30)}"
          ++ addLine "      timeout: ${toString (server.timeout or 60)}"
        else
          # stdio
          addLine "      command: ${server.command}"
          ++ lib.optional (server ? args && server.args != [])
          ("      args:\n" + lib.concatStringsSep "\n" (map (a: "        - ${a}") server.args))
          ++ addLine "      connect_timeout: ${toString (server.connectTimeout or 30)}"
          ++ addLine "      timeout: ${toString (server.timeout or 60)}"
          ++ lib.optional (server ? description)
          "      description: ${server.description}"
      );
  in
    lib.concatStringsSep "\n" (lib.mapAttrsToList mkServerBlock servers);

  hermesMcpYaml = pkgs.writeText "hermes-mcp-servers.yaml" ''
        mcp_servers:
    ${mkHermesMcpServers allServers}
  '';


  # ── C5: Generate NetworkPolicy per server ───────────────────────────────
  mkNetworkPolicy = name: server:
    if server ? ssePort
    then {
      "mcp".NetworkPolicy."allow-${name}-ingress" = {
        metadata.labels = {
          "app.kubernetes.io/managed-by" = "easykubenix";
          "mcp-server" = name;
        };
        spec = {
          podSelector.matchLabels.app = name;
          policyTypes = ["Ingress"];
          ingress = [
            {
              from = [
                {namespaceSelector.matchLabels.name = "ingress-system";}
                {ipBlock.cidr = "10.1.1.0/24";}
              ];
              ports = [
                {
                  protocol = "TCP";
                  port = server.ssePort;
                }
              ];
            }
          ];
        };
      };
    }
    else {};

  networkPolicies = lib.mkMerge (lib.mapAttrsToList mkNetworkPolicy allServers);

  # ── C6: Casdoor gateway registration data ───────────────────────────────
  # Generates a JSON file with Casdoor app registration data for MCP servers
  mkCasdoorAppData = servers: let
    serversWithApps = lib.filterAttrs (_: s: s.casdoorApp != null) servers;
  in
    pkgs.writeText "casdoor-mcp-apps.json" (
      builtins.toJSON (
        lib.mapAttrsToList (name: server: {
          inherit name;
          appName = server.casdoorApp;
          displayName = "${name} MCP Server";
          description = server.description or "";
          redirectUris = ["http://localhost:${toString (server.ssePort or 0)}/oauth2/callback"];
          grantTypes = ["authorization_code" "client_credentials"];
          scopes = ["openid" "profile" "email" "mcp"];
        })
        serversWithApps
      )
    );
in {
  options.services.mcp-registry = {
    enable = mkEnableOption "MCP Server Registry — single source of truth for all MCP servers";

    defaultServers = mkOption {
      type = types.attrsOf types.anything;
      default = defaultServers;
      description = "Default MCP server definitions";
      readOnly = true;
    };

    extraServers = mkOption {
      type = types.attrsOf types.anything;
      default = {};
      description = "Additional MCP servers to merge with defaults";
    };

    # C2: Claude Code generation
    generateClaudeCode = mkEnableOption "Generate Claude Code settings.json from registry";

    claudeCodeUser = mkOption {
      type = types.str;
      default = "j_kro";
      description = "User whose Claude Code config to manage";
    };

    # C3: Hermes generation
    generateHermes = mkEnableOption "Generate Hermes config.yaml mcp_servers from registry";

    hermesUser = mkOption {
      type = types.str;
      default = "j_kro";
      description = "User whose Hermes config to manage";
    };


    # C5: NetworkPolicy generation
    generateNetworkPolicies = mkEnableOption "Generate NetworkPolicy per MCP server";

    # C6: Casdoor registration
    generateCasdoorApps = mkEnableOption "Generate Casdoor app registration data for MCP servers";
  };

  config = mkIf cfg.enable {
    # ── C2: Claude Code settings.json generation ──────────────────────────
    system.activationScripts.claude-code-mcp-config = mkIf cfg.generateClaudeCode (
      lib.stringAfter ["users"] ''
        CLAUDE_CONFIG="/home/${cfg.claudeCodeUser}/.claude/settings.json"

        mkdir -p "/home/${cfg.claudeCodeUser}/.claude"

        # Use the prebaked JSON file in the Nix store rather than embedding JSON
        # into a bash command line. The store path is a single literal token,
        # so there's no shell-quoting risk even if entries contain double
        # quotes, backslashes, newlines, or shell metacharacters.
        CLAUDE_CODE_MCP_JSON="${claudeCodeJson}"

        if [ -f "$CLAUDE_CONFIG" ]; then
          # Merge mcpServers into existing settings.json.
          # --slurpfile loads the file as an array; [0] picks the JSON object.
          ${pkgs.jq}/bin/jq \
            '.mcpServers |= (.mcpServers // {}) + $mcp[0].mcpServers' \
            --slurpfile mcp "$CLAUDE_CODE_MCP_JSON" \
            "$CLAUDE_CONFIG" > "$CLAUDE_CONFIG.tmp" && mv "$CLAUDE_CONFIG.tmp" "$CLAUDE_CONFIG"
        else
          # No prior config — copy the Nix-managed JSON verbatim.
          cp "$CLAUDE_CODE_MCP_JSON" "$CLAUDE_CONFIG"
        fi

        chown ${cfg.claudeCodeUser}:users "$CLAUDE_CONFIG" 2>/dev/null || true
        chmod 644 "$CLAUDE_CONFIG" 2>/dev/null || true
      ''
    );

    # ── C3: Hermes config.yaml mcp_servers generation ─────────────────────
    systemd.services.hermes-mcp-registry = mkIf false {
      description = "Inject MCP registry servers into Hermes config";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      path = with pkgs; [python3 coreutils];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        RemainAfterExit = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = ["/home/${cfg.hermesUser}/.hermes"];

        ExecStart = pkgs.writeShellScript "hermes-mcp-registry" ''
          set -euo pipefail

          HERMES_CONFIG="/home/${cfg.hermesUser}/.hermes/config.yaml"
          MCP_BLOCK="${hermesMcpYaml}"

          if [ ! -f "$HERMES_CONFIG" ]; then
            echo "[hermes-mcp-registry] No config.yaml found, skipping"
            exit 0
          fi

          # Merge mcp_servers block using Python
          python3 -c "
          import sys
          config_path = sys.argv[1]
          mcp_path = sys.argv[2]
          with open(config_path) as f:
              lines = f.readlines()
          with open(mcp_path) as f:
              mcp_block = f.read().strip()
          in_mcp = False
          filtered = []
          for line in lines:
              if line.startswith('mcp_servers:') or line.startswith('mcp_servers: '):
                  in_mcp = True
                  continue
              if in_mcp:
                  if line.startswith(" ") or \t in line or line.strip() == "":
                      continue
                  in_mcp = False
              filtered.append(line)
          content = "".join(filtered).rstrip()
          marker = "smart_model_routing:"
          full = content.split(marker, 1)
          if len(full) == 2:
              result = full[0] + mcp_block + chr(10) + chr(10) + marker + full[1]
          else:
              result = content + chr(10) + chr(10) + mcp_block + chr(10)
          with open(config_path, 'w') as f:
              f.write(result)
          " "$HERMES_CONFIG" "$MCP_BLOCK"

          chown ${cfg.hermesUser}:users "$HERMES_CONFIG" 2>/dev/null || true
          chmod 600 "$HERMES_CONFIG" 2>/dev/null || true

          echo "[hermes-mcp-registry] MCP servers configured from registry"
        '';
      };
    };

    # ── C6: Casdoor app registration data ─────────────────────────────────
    environment.etc."mcp-registry/casdoor-apps.json" = mkIf cfg.generateCasdoorApps {
      source = mkCasdoorAppData allServers;
      mode = "0644";
    };

    # Export packages for external consumption
    environment.systemPackages = mkIf cfg.generateClaudeCode [
      (pkgs.writeShellScriptBin "mcp-registry-dump" ''
        echo "=== MCP Server Registry ==="
        echo "Total servers: ${toString (builtins.length (builtins.attrNames allServers))}"
        echo "stdio: ${toString (builtins.length (builtins.attrNames stdioServers))}"
        echo "sse: ${toString (builtins.length (builtins.attrNames sseServers))}"
        echo "http: ${toString (builtins.length (builtins.attrNames httpServers))}"
        echo ""
        echo "=== Servers ==="
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (
            name: server: "echo '${name}: ${server.type} (${server.scope}) - ${server.description or "no description"}'"
          )
          allServers)}
      '')
    ];

    # Public helpers for use by other modules (via config.lib.mcp-registry)
    lib.mcp-registry = {
      inherit allServers stdioServers sseServers httpServers localServers clusterServers;
      inherit mkClaudeCodeMcpServers mkHermesMcpServers mkNetworkPolicy;
      inherit claudeCodeJson hermesMcpYaml networkPolicies;
    };
  };
}

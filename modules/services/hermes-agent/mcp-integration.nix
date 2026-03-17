# Hermes MCP Integration
# Connects Hermes Agent to the existing MCP Broker at :9000
{ config, lib, pkgs, ... }:
let
  cfg = config.services.hermes-agent;
  aiGateway = config.services.ai-inference;
in lib.mkIf (cfg.enable && aiGateway.enable) {
  # MCP configuration file for Hermes
  environment.etc."hermes/mcp-servers.yaml" = {
    enable = true;
    text = ''
# Hermes MCP Configuration
# Auto-generated from NixOS AI Gateway MCP Broker

mcpServers:
  # Local MCP Broker (AI Gateway)
  ai-gateway:
    url: http://127.0.0.1:9000/mcp
    description: "Local AI Gateway MCP Broker - 12+ tools available"

  # SearXNG integration (if enabled)
  searxng:
    url: http://127.0.0.1:9000/mcp/searxng
    description: "Private search engine via AI Gateway"

  # Web Search (if enabled)
  web-search-prime:
    url: http://127.0.0.1:9000/mcp/web_search_prime
    description: "Web search via AI Gateway"

  # Context7 Documentation (if enabled)
  context7:
    url: http://127.0.0.1:9000/mcp/context7-query-docs
    description: "NixOS & library documentation lookup"
    notes: "Query: 'How do I use <library>?'"

# Tool categories available through MCP:
# - Search: web-search-prime, searxng
# - Documentation: context7-query-docs
# - Code operations: (various)
# - File operations: (various)
# - System operations: (various)
#
# Run: hermes "What MCP tools are available?"
'';
  };

  # Wrapper script to inject MCP config into Hermes environment
  environment.etc."hermes/profile.d/hermes-mcp.sh" = {
    enable = true;
    text = ''
#!/usr/bin/env bash
# Hermes MCP Integration
# Sets up environment for Hermes to use MCP tools

# MCP Configuration path
export HERMES_MCP_CONFIG="/etc/hermes/mcp-servers.yaml"

# AI Gateway endpoint for Hermes
export HERMES_AI_GATEWAY_URL="${aiGateway.url}"

# OpenAI-compatible configuration
export OPENAI_API_KEY="not-needed"
export OPENAI_BASE_URL="${aiGateway.url}"

# Enable MCP tools in Hermes
export HERMES_ENABLE_MCP="true"

# Optional: MCP-specific settings
export HERMES_MCP_TIMEOUT="30"  # 30 second timeout for MCP calls
export HERMES_MCP_RETRY="3"     # Retry failed MCP calls 3 times

echo "[Hermes MCP] Configuration loaded"
echo "[Hermes MCP] MCP Config: $HERMES_MCP_CONFIG"
echo "[Hermes MCP] AI Gateway: $HERMES_AI_GATEWAY_URL"
'';
    executable = true;
  };

  # Systemd user service to keep MCP tools synced
  systemd.user.services.hermes-mcp-sync = {
    description = "Sync MCP tool schemas from AI Gateway to Hermes";
    script = ''
      #!/usr/bin/env bash
      set -e

      echo "[Hermes MCP Sync] Fetching tool schemas from AI Gateway..."

      # Get available tools from MCP Broker
      TOOLS=$(curl -s http://127.0.0.1:9000/mcp/tools 2>/dev/null || echo "")

      if [[ -n "$TOOLS" ]]; then
        # Store tools list for Hermes
        echo "$TOOLS" > /tmp/hermes-mcp-tools.json
        echo "[Hermes MCP Sync] ✓ Synced $(echo "$TOOLS" | jq '.tools | length' 2>/dev/null || echo "0") tools"
      else
        echo "[Hermes MCP Sync] ⚠️  Could not reach MCP Broker at 127.0.0.1:9000"
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      User = cfg.user;
    };
    wantedBy = [ "default.target" ];
  };

  # Timer to sync MCP tools every 5 minutes
  systemd.user.timers.hermes-mcp-sync = {
    description = "Periodic MCP tool sync from AI Gateway";
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "5min";
      AccuracySec = "1s";
    };
    wantedBy = [ "default.target" ];
  };
}

{
  cfg,
  pkgs,
  mkMcpServersJson,
  gatewayUrl,
}: {
  mkClaudeMcpJson = pkgs.writeShellScript "generate-claude-mcp" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    CTX7_KEY_PATH="${cfg.context7ApiKeyFile}"
    CONTEXT7_API_KEY="$(cat $CTX7_KEY_PATH 2>/dev/null || echo)"
    ${pkgs.jq}/bin/jq -n \
      --arg ctx7_key "$CONTEXT7_API_KEY" \
      '{
        "mcpServers": {
          ${mkMcpServersJson {
      keyMode = "resolved";
      extraServers = {
        nixos = {
          command = "uvx";
          args = ["mcp-nixos"];
        };
      };
    }}
        }
      }' > "/home/${cfg.user}/.config/claude/mcp.json"
    chown ${cfg.user}:users "/home/${cfg.user}/.config/claude/mcp.json"
    chmod 644 "/home/${cfg.user}/.config/claude/mcp.json"
    echo "[ai-coding-tools] Claude Code MCP config generated"
  '';
}

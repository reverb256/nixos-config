{
  config,
  lib,
  pkgs,
  ...
}: {
  # MCP Server Configuration for Web Search and Tool Integration
  options = {
    services.mcp-server = {
      enable = lib.mkEnableOption "MCP server for web search and tool integration";
      port = lib.mkOption {
        type = lib.types.ints.positive;
        description = "Port for MCP server";
        default = 3000;
      };
      logLevel = lib.mkOption {
        type = lib.types.enum ["error" "warn" "info" "debug"];
        description = "Log level for MCP server";
        default = "info";
      };
    };
  };

  config = {
    services.mcp-server = {
      inherit (config.services.mcp-server) enable;
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = 5;
        User = "j_kro";
        Group = "j_kro";
        ExecStart = "${pkgs.python3}/bin/python3 $HOME/.claude/mcp-server.py";
        Environment = [
          "HOME=/home/j_kro"
          "PATH=${pkgs.python3}/bin:${pkgs.nix}/bin"
        ];
        ExecStartPre = "${pkgs.writeShellScriptBin "mcp-setup" ''
          #!/bin/bash
          set -e
          mkdir -p $HOME/.claude
          chown j_kro:j_kro $HOME/.claude
        ''}";
      };
    };
  };
}

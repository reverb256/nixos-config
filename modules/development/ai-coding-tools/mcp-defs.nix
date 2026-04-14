# Shared MCP server definitions and JSON generation function
# Used by all AI coding tool generators
#
# This module is NOT a NixOS module — it's a plain Nix function
# that returns shared data and the mkMcpServersJson helper.
#
# Local stdio servers are derived from the shared registry at
# modules/services/mcp-server-registry.nix to keep server definitions
# in sync between coding tools (JSON generation) and service modules
# (wrapper script generation).
{ lib }:
let
  # Import shared server registry (single source of truth)
  registry = import ../../services/mcp-server-registry.nix { inherit lib; };

  context7ApiKeyRef = "$CONTEXT7_API_KEY";

  # Z.AI HTTP MCP servers (identical across all tools)
  zaiHttpServers = {
    web-search-prime = {
      type = "http";
      url = "https://api.z.ai/api/mcp/web_search_prime/mcp";
      headers.Authorization = "Bearer $ZAI_API_KEY";
    };
    web-reader = {
      type = "http";
      url = "https://api.z.ai/api/mcp/web_reader/mcp";
      headers.Authorization = "Bearer $ZAI_API_KEY";
    };
    zread = {
      type = "http";
      url = "https://api.z.ai/api/mcp/zread/mcp";
      headers.Authorization = "Bearer $ZAI_API_KEY";
    };
  };

  zaiStdioServer = {
    type = "stdio";
    command = "npx";
    args = [
      "-y"
      "@z_ai/mcp-server"
    ];
    env = {
      Z_AI_MODE = "ZAI";
      Z_AI_API_KEY = "$ZAI_API_KEY";
    };
  };

  # Build local stdio servers from the shared registry.
  # This ensures the server names/commands in JSON configs match the
  # wrapper scripts installed by mcp-servers.nix.
  mkLocalServer = name: _def: {
    command = registry.mkCommand name;
  };

  # Servers with additional config beyond bare command
  localStdioServers = (lib.mapAttrs mkLocalServer registry.servers) // {
    # Override: filesystem needs args for allowed paths
    filesystem = {
      command = "mcp-filesystem";
      args = [
        "/etc/nixos"
        "/home/j_kro"
      ];
    };
    # Override: context7 needs API key env var
    context7 = {
      command = "mcp-context7";
      env.CONTEXT7_API_KEY = context7ApiKeyRef;
    };
    # Override: chrome-devtools uses npx directly (not mcp- wrapper)
    chrome-devtools = {
      command = "npx";
      args = [
        "-y"
        "chrome-devtools-mcp@latest"
      ];
    };
  };

  # Full MCP set: Z.AI stdio + Z.AI HTTP + local stdio
  fullMcpSet =
    localStdioServers
    // {
      "zai-mcp-server" = zaiStdioServer;
    }
    // zaiHttpServers;

  # ---------------------------------------------------------------------------
  # mkMcpServersJson: Generate MCP server JSON fragments for jq
  #
  # Parameters:
  #   keyMode:      "env" ($VAR references) or "resolved" (file-read keys)
  #   extraServers: additional servers beyond fullMcpSet
  #   disabled:     whether to add "disabled": false (Droid)
  # ---------------------------------------------------------------------------
  mkMcpServersJson =
    {
      keyMode ? "resolved",
      extraServers ? { },
      disabled ? false,
    }:
    let
      resolveAuth = keyMode == "env";
      zaiKey = if resolveAuth then "$ZAI_API_KEY" else "$zai_key";
      ctx7Key = if resolveAuth then context7ApiKeyRef else "$ctx7_key";

      allServers = fullMcpSet // extraServers;

      mkServerFragment =
        name: server:
        let
          isHttp = server.type or null == "http";
          isZaiStdio = name == "zai-mcp-server";
          isContext7 = name == "context7";

          envBlock =
            if server ? env && server.env != null then
              let
                envEntries = lib.mapAttrsToList (
                  k: v:
                  if isZaiStdio && k == "Z_AI_API_KEY" then
                    "\"${k}\": \"${zaiKey}\""
                  else if isContext7 && k == "CONTEXT7_API_KEY" then
                    "\"${k}\": \"${ctx7Key}\""
                  else
                    "\"${k}\": \"${v}\""
                ) server.env;
              in
              ''
                , "env": { ${lib.concatStringsSep ", " envEntries} }
              ''
            else
              "";

          argsBlock =
            if server ? args && server.args != null then
              ''
                , "args": [${lib.concatStringsSep ", " (map (a: "\"${a}\"") server.args)}]
              ''
            else
              "";

          headersBlock =
            if isHttp && server ? headers && server.headers != null then
              let
                headerEntries = lib.mapAttrsToList (
                  k: v:
                  if k == "Authorization" then
                    if resolveAuth then "\"${k}\": \"${v}\"" else "\"${k}\": (\"Bearer \" + $zai_key)"
                  else
                    "\"${k}\": \"${v}\""
                ) server.headers;
              in
              ''
                , "headers": { ${lib.concatStringsSep ", " headerEntries} }
              ''
            else
              "";

          disabledBlock = lib.optionalString disabled ''
            , "disabled": false
          '';

          commandBlock =
            if server ? command && server.command != null then
              ''
                , "command": "${server.command}"
              ''
            else
              "";

          typeBlock =
            if isHttp then
              ''
                , "type": "http"
                , "url": "${server.url}"
              ''
            else
              "";
        in
        ''
          "${name}": {${typeBlock}${commandBlock}${argsBlock}${envBlock}${headersBlock}${disabledBlock}}
        '';

      serverFragments = lib.mapAttrsToList mkServerFragment allServers;
    in
    lib.concatStringsSep "," serverFragments;
in
{
  inherit mkMcpServersJson fullMcpSet;
}

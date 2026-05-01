{lib}: let
  registry = import ../../services/mcp-server-registry.nix {inherit lib;};

  context7ApiKeyRef = "$CONTEXT7_API_KEY";

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

  mkLocalServer = name: def:
    if def.type == "custom" && def ? command then {
      # Custom servers with explicit command (searxng, casdoor, etc.)
      command = def.command;
    } // (lib.optionalAttrs (def ? args) {args = def.args;})
      // (lib.optionalAttrs (def ? env) {env = def.env;})
    else if def.type == "nix" then {
      # Nix packages provide mcp-<name> commands directly
      command = registry.mkCommand name;
    }
    else if def.type == "custom" then {
      # Custom type without command → use mcp-<name> from PATH
      command = registry.mkCommand name;
    }
    else {
      # npm/uvx types → use mcp-<name> from PATH
      command = registry.mkCommand name;
    };

  # Filter out claudeOnly servers from local stdio (they go in extraServers)
  localStdioServers =
    lib.filterAttrs (name: _: !(registry.servers.${name}.claudeOnly or false))
    (lib.mapAttrs mkLocalServer registry.servers)
    // {
      filesystem = {
        command = "mcp-filesystem";
        args = ["/etc/nixos" "/home/j_kro"];
      };
      context7 = {
        command = "mcp-context7";
        env.CONTEXT7_API_KEY = context7ApiKeyRef;
      };
      chrome-devtools = {
        command = "npx";
        args = ["-y" "chrome-devtools-mcp@latest"];
      };
      casdoor = {
        command = "python3";
        args = ["/data/agents/mcp-bridges/casdoor-mcp-bridge.py"];
      };
    };

  fullMcpSet =
    localStdioServers
    // {
      "zai-mcp-server" = zaiStdioServer;
    }
    // zaiHttpServers;

  mkMcpServersJson = {
    keyMode ? "resolved",
    extraServers ? {},
    disabled ? false,
  }: let
    resolveAuth = keyMode == "env";
    zaiKey =
      if resolveAuth
      then "$ZAI_API_KEY"
      else "$zai_key";
    ctx7Key =
      if resolveAuth
      then context7ApiKeyRef
      else "$ctx7_key";

    allServers = fullMcpSet // extraServers;

    mkServerFragment = name: server: let
      isHttp = server.type or null == "http";
      isZaiStdio = name == "zai-mcp-server";
      isContext7 = name == "context7";

      resolveEnv = k: v:
        if isZaiStdio && k == "Z_AI_API_KEY"
        then zaiKey
        else if isContext7 && k == "CONTEXT7_API_KEY"
        then ctx7Key
        else v;

      resolveHeader = k: v:
        if k == "Authorization" && !resolveAuth
        then "(\"Bearer \" + $zai_key)"
        else "\"" + v + "\"";

      fields = lib.filter (s: s != "") [
        (lib.optionalString isHttp "\"type\": \"http\"")
        (lib.optionalString (isHttp && server ? url)
          ("\"url\": \"" + server.url + "\""))
        (lib.optionalString (server ? command && server.command != null)
          ("\"command\": \"" + server.command + "\""))
        (lib.optionalString (server ? args && server.args != null)
          ("\"args\": [" + (lib.concatStringsSep ", " (map (a: "\"" + a + "\"") server.args)) + "]"))
        (lib.optionalString (server ? env && server.env != null)
          ("\"env\": { "
            + lib.concatStringsSep ", " (
              lib.mapAttrsToList (k: v: "\"" + k + "\": \"" + (resolveEnv k v) + "\"") server.env
            )
            + " }"))
        (lib.optionalString (isHttp && server ? headers && server.headers != null)
          ("\"headers\": { "
            + lib.concatStringsSep ", " (
              lib.mapAttrsToList (k: v: "\"" + k + "\": " + (resolveHeader k v)) server.headers
            )
            + " }"))
        (lib.optionalString disabled "\"disabled\": false")
      ];
    in
      "\"" + name + "\": {" + (lib.concatStringsSep ", " fields) + "}";

    serverFragments = lib.mapAttrsToList mkServerFragment allServers;
  in
    lib.concatStringsSep ",\n    " serverFragments;
in {
  inherit mkMcpServersJson fullMcpSet;
}
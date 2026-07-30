{lib}: let
  context7ApiKeyRef = "$CONTEXT7_API_KEY";

  # Full MCP server set — kept in sync with the inline definitions
  # in modules/development/ai-coding-tools.nix so the sub-files
  # (claude.nix, droid.nix, crush.nix, opencode.nix, pi.nix)
  # produce identical output.
  localStdioServers = {
    filesystem = {
      command = "mcp-filesystem";
      args = ["/etc/nixos" "/home/j_kro"];
    };
    git = {
      command = "mcp-git";
    };
    fetch = {
      command = "mcp-fetch";
    };
    playwright = {
      command = "mcp-playwright";
    };
    context7 = {
      command = "mcp-context7";
      env.CONTEXT7_API_KEY = context7ApiKeyRef;
    };
    chrome-devtools = {
      command = "npx";
      args = ["-y" "chrome-devtools-mcp@latest"];
    };
    gateway = {
      command = "mcp-gateway-bridge";
    };
    hound = {
      command = "/data/agents/mcp-bridges/hound-mcp.sh";
      description = "Web fetch + crawl + search + Cloudflare bypass + PDF OCR";
    };
  };

  # Z.AI MCP servers (HTTP + stdio). These were removed in the 2026-07-15
  # sub-file draft but are still active in the main ai-coding-tools.nix.
  # Restored 2026-07-29 to match the authoritative inline config.
  zaiMcpServers = {
    zai-mcp-server = {
      type = "stdio";
      command = "npx";
      args = ["-y" "@z_ai/mcp-server"];
      env.Z_AI_MODE = "ZAI";
      env.Z_AI_API_KEY = "$ZAI_API_KEY";
    };
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

  mkMcpServersJson = {
    keyMode ? "resolved",
    extraServers ? {},
    disabled ? false,
  }: let
    isEnv = keyMode == "env";
    ctx7Key = if isEnv then context7ApiKeyRef else "$ctx7_key";
    zaiKey = if isEnv then "$ZAI_API_KEY" else "$zai_key";

    allServers = localStdioServers // zaiMcpServers // extraServers;

    mkServerFragment = name: server: let
      isHttp = server.type or null == "http";
      isContext7 = name == "context7";
      isZai = lib.hasPrefix "zai-" name || lib.hasPrefix "web-" name || name == "zread";

      resolveEnv = k: v:
        if isContext7 && k == "CONTEXT7_API_KEY" then ctx7Key
        else if isZai && k == "Z_AI_API_KEY" then zaiKey
        else v;

      resolveHeader = _k: v: "\"" + v + "\"";

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
  inherit mkMcpServersJson;
  fullMcpSet = localStdioServers // zaiMcpServers;
}

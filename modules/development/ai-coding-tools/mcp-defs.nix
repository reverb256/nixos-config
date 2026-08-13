{lib}: let
  context7ApiKeyRef = "$CONTEXT7_API_KEY";

  # Local MCP servers shared by the coding tools.
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

  mkMcpServersJson = {
    keyMode ? "resolved",
    extraServers ? {},
    disabled ? false,
  }: let
    isEnv = keyMode == "env";
    ctx7Key = if isEnv then context7ApiKeyRef else "$ctx7_key";
    allServers = localStdioServers // extraServers;

    mkServerFragment = name: server: let
      isHttp = server.type or null == "http";
      isContext7 = name == "context7";

      resolveEnv = k: v:
        if isContext7 && k == "CONTEXT7_API_KEY" then ctx7Key else v;

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
  fullMcpSet = localStdioServers;
}

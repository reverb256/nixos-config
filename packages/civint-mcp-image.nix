{ dockerTools, buildEnv, nodejs_22, bash, coreutils, stdenvNoCC
, src ? builtins.path { path = /data/projects/own/frostbite-data-pipeline; name = "civint-mcp-source"; }
}:

let
  # Bundle app + installed node_modules into a clean app directory
  civintDist = stdenvNoCC.mkDerivation {
    name = "civint-mcp-dist";
    inherit src;
    installPhase = ''
      mkdir -p $out/app
      cp -r $src/package.json $src/package-lock.json $out/app/
      cp -r $src/packages $out/app/
      cp -r $src/dist $out/app/
      cp -r $src/node_modules $out/app/
    '';
  };
in
dockerTools.buildImage {
  name = "civint-mcp";
  tag = "nixos";

  copyToRoot = buildEnv {
    name = "civint-mcp-root";
    paths = [
      civintDist
      nodejs_22
      bash
      coreutils
    ];
    pathsToLink = [ "/bin" "/app" ];
    ignoreCollisions = true;
  };

  config = {
    Cmd = [
      "${nodejs_22}/bin/node"
      "/app/packages/mcp-server/dist/index.js"
    ];
    WorkingDir = "/app";
    Env = [
      "HOME=/tmp"
      "PATH=/bin"
      "PORT=3002"
    ];
    ExposedPorts = { "3002/tcp" = {}; };
    Labels = {
      "org.opencontainers.image.title" = "CivInt MCP Server";
      "org.opencontainers.image.description" = "Canadian sovereign data pipeline MCP server";
      "org.opencontainers.image.source" = "https://github.com/reverb256/frostbite-data-pipeline";
    };
  };
}

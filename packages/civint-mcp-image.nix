{ dockerTools, buildEnv, nodejs_22, bash, coreutils, stdenvNoCC, pnpm
, src ? builtins.path { path = /data/projects/own/civint; name = "civint-mcp-source"; }
}:

let
  civintDist = stdenvNoCC.mkDerivation {
    name = "civint-mcp-dist";
    inherit src;
    buildInputs = [ nodejs_22 pnpm ];
    buildPhase = ''
      export HOME=$TMPDIR
      corepack enable
      pnpm install --frozen-lockfile --dir $src
      cd $src
      pnpm --filter @civint/pipeline-core build
      pnpm --filter @civint/mcp-server build
    '';
    installPhase = ''
      mkdir -p $out/app
      cp -r $src/package.json $out/app/
      cp -r $src/pnpm-lock.yaml $out/app/
      cp -r $src/packages/pipeline-core/dist $out/app/packages/pipeline-core/
      cp -r $src/packages/pipeline-core/package.json $out/app/packages/pipeline-core/
      cp -r $src/packages/mcp-server/dist $out/app/packages/mcp-server/
      cp -r $src/packages/mcp-server/package.json $out/app/packages/mcp-server/
      cp -r $src/packages/engine/dist $out/app/packages/engine/
      cp -r $src/packages/engine/package.json $out/app/packages/engine/
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
      "NODE_ENV=production"
    ];
    ExposedPorts = { "3002/tcp" = {}; };
    Labels = {
      "org.opencontainers.image.title" = "CivInt MCP Server";
      "org.opencontainers.image.description" = "Canadian sovereign data pipeline MCP server";
      "org.opencontainers.image.source" = "https://github.com/reverb256/civint";
    };
  };
}

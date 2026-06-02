{
  dockerTools,
  buildEnv,
  nodejs_22,
  bash,
  coreutils,
  stdenvNoCC,
  pnpm,
  src ?
    builtins.path {
      path = /data/projects/own/maplespike;
      name = "maplespike-mcp-source";
    },
}: let
  mcpDist = stdenvNoCC.mkDerivation {
    name = "maplespike-mcp-dist";
    inherit src;
    buildInputs = [nodejs_22 pnpm];
    buildPhase = ''
      export HOME=$TMPDIR
      corepack enable
      pnpm install --frozen-lockfile --dir $src
      cd $src
      pnpm --filter @maplespike/pipeline-core build
      pnpm --filter @maplespike/mcp-server build
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
    name = "maplespike-mcp";
    tag = "nixos";

    copyToRoot = buildEnv {
      name = "maplespike-mcp-root";
      paths = [
        mcpDist
        nodejs_22
        bash
        coreutils
      ];
      pathsToLink = ["/bin" "/app"];
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
        "PORT=3001"
        "NODE_ENV=production"
        "MAPLESPIKE_API_URL=http://maplespike-api:8084/v1"
        "MAPLESPIKE_API_KEY=maplespike-dev-key"
      ];
      ExposedPorts = {"3001/tcp" = {};};
      Labels = {
        "org.opencontainers.image.title" = "MapleSpike MCP Server";
        "org.opencontainers.image.description" = "Canadian government data pipeline MCP server";
        "org.opencontainers.image.source" = "https://github.com/reverb256/maplespike";
      };
    };
  }

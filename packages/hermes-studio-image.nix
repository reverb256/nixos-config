# Hermes Studio OCI container image — built from source
# Repo: https://github.com/JPeetz/Hermes-Studio
# Pinned to main rev 4788d9c (2026-04-19)
#
# Build: nix build .#hermes-studio-image
# Load into K3s: docker load < result && docker tag hermes-studio:1.18.1 localhost:5000/hermes-studio:1.18.1
#
# NOTE: This builds the full Node.js app with pnpm + vite.
#       better-sqlite3 requires native build tools (python3, make, cc).
#       If Nix build fails, fallback: docker build on nexus from the cloned repo.

{ dockerTools, buildEnv, bash, coreutils, nodejs_22, fetchFromGitHub
, pnpm_10, python3, pkg-config, gcc, stdenv, cacert, makeWrapper
}:

let
  version = "1.18.1";
  rev = "4788d9cebf0cf1c4564e6da4ee65752a9d746517";

  src = fetchFromGitHub {
    owner = "JPeetz";
    repo = "Hermes-Studio";
    inherit rev;
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # TODO: fill after first fetch
  };

  hermes-studio-app = stdenv.mkDerivation rec {
    pname = "hermes-studio";
    inherit version src;

    nativeBuildInputs = [ nodejs_22 pnpm_10.configHook python3 pkg-config gcc makeWrapper ];
    buildInputs = [ gcc python3 ];

    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";

    pnpmDeps = pnpm_10.fetchDeps {
      inherit pname version src;
      hash = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="; # TODO: fill after first fetch
    };

    buildPhase = ''
      runHook preBuild
      pnpm build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/app
      cp -r dist $out/app/
      cp -r node_modules $out/app/
      cp package.json server-entry.js $out/app/
      mkdir -p $out/bin
      makeWrapper ${nodejs_22}/bin/node $out/bin/hermes-studio \
        --add-flags "$out/app/server-entry.js" \
        --set NODE_ENV production \
        --set NODE_OPTIONS "--max-old-space-size=2048"
      runHook postInstall
    '';
  };

in
dockerTools.buildImage {
  name = "hermes-studio";
  tag = version;

  copyToRoot = buildEnv {
    name = "hermes-studio-root";
    paths = [
      hermes-studio-app
      bash
      coreutils
      nodejs_22
      cacert
    ];
    pathsToLink = [
      "/bin"
      "/etc"
      "/lib"
      "/app"
    ];
  };

  config = {
    Cmd = [
      "${nodejs_22}/bin/node"
      "${hermes-studio-app}/app/server-entry.js"
    ];
    WorkingDir = "/app";
    Env = [
      "NODE_ENV=production"
      "NODE_OPTIONS=--max-old-space-size=2048"
      "HOME=/app"
      "PATH=/bin"
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
    ];
    ExposedPorts = {
      "3000/tcp" = { };
    };
    Labels = {
      "org.opencontainers.image.title" = "Hermes Studio";
      "org.opencontainers.image.description" = "Full-featured web UI for hermes-agent";
      "org.opencontainers.image.version" = version;
      "org.opencontainers.image.source" = "https://github.com/JPeetz/Hermes-Studio";
    };
  };
}

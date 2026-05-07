{
  pkgs,
  hermesSrc,
}:
pkgs.buildNpmPackage {
  pname = "hermes-agent-web-dist";
  version = "0.10.0";

  src = hermesSrc;
  sourceRoot = "source/web";

  npmDepsHash = "sha256-Y0pOzdFG8BLjfvCLmsvqYpjxFjAQabXp1i7X9W/cCU4=";

  # Don't let buildNpmPackage run npm build - we do it ourselves
  dontNpmBuild = true;

  buildPhase = ''
    npx vite build --outDir $out
  '';

  installPhase = "echo ok";
}

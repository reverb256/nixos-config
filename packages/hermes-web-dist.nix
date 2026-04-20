{ pkgs, hermesSrc }:
pkgs.buildNpmPackage {
  pname = "hermes-agent-web-dist";
  version = "0.9.0";

  src = hermesSrc;
  sourceRoot = "source/web";

  npmDepsHash = "sha256-Kh7lX3iWMM25E2kotpJFouZxtAx0n0fOsHeyPllqDDg=";

  # Don't let buildNpmPackage run npm build - we do it ourselves
  dontNpmBuild = true;

  buildPhase = ''
    npx vite build --outDir $out
  '';

  installPhase = "echo ok";
}

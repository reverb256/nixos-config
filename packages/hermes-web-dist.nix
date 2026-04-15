{
  pkgs,
  hermesSrc,
}:
pkgs.stdenv.mkDerivation {
  pname = "hermes-agent-web-dist";
  version = "0.9.0";

  src = hermesSrc;

  sourceRoot = "source/web";

  nativeBuildInputs = with pkgs; [
    nodejs_20
  ];

  buildPhase = ''
    npm install --ignore-scripts
    npm run build
  '';

  installPhase = ''
    mkdir -p $out
    # The build outputs to ../hermes_cli/web_dist
    cp -r ../hermes_cli/web_dist/* $out/
  '';
}

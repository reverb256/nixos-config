{ lib, buildNpmPackage, fetchurl, nodejs_22 }:

buildNpmPackage rec {
  pname = "lmstudio";
  version = "0.0.32";

  src = fetchurl {
    url = "https://registry.npmjs.org/lmstudio/-/lmstudio-${version}.tgz";
    hash = "sha256-SHA256PLACEHOLDER";
  };

  npmDepsHash = "sha256-NPMDEPSPLACEHOLDER";
  npmDepsFetcherVersion = 2;

  nativeBuildInputs = [ nodejs_22 ];

  postBuild = ''
    # The npm package exports dist/index.js as the main CLI
    cp dist/index.js lmstudio
    chmod +x lmstudio
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp lmstudio $out/bin/
    wrapProgram $out/bin/lmstudio \
      --prefix PATH : ${lib.makeBinPath [ nodejs_22 ]}
  '';

  meta = with lib; {
    description = "LM Studio CLI tool for managing local LLM models";
    homepage = "https://lmstudio.ai";
    license = licenses.unfree; # LM Studio likely has a custom license
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
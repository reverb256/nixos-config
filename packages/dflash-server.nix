{
  lib,
  python3Packages,
}:
python3Packages.buildPythonApplication rec {
  pname = "dflash-server";
  version = "0.1.0";
  format = "other";

  src = ./dflash-server.py;

  propagatedBuildInputs = with python3Packages; [
    fastapi
    uvicorn
    transformers
    sentencepiece
    protobuf
    tokenizers
  ];

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp $src $out/bin/dflash-server
    chmod +x $out/bin/dflash-server
    patchShebangs $out/bin/dflash-server
    runHook postInstall
  '';

  makeWrapperArgs = [
    "--prefix PATH : ${lib.makeBinPath (with python3Packages; [
      (python3Packages.python.withPackages (ps: propagatedBuildInputs))
    ])}"
  ];

  meta = {
    description = "OpenAI-compatible server wrapper for Lucebox DFlash test_dflash";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}

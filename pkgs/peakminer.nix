{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  ...
}:
stdenv.mkDerivation {
  pname = "peakminer";
  version = "2.8.2";

  src = fetchurl {
    url = "https://github.com/kryptex-miners-org/kryptex-miners/releases/download/peakminer-2-8-2/peakminer-2.8.2.tar.gz";
    hash = "sha256-iVUAgmTf4E6KrtyrZCkfdsCFXsGGdlD7sxFYTut6Jm8=";
  };

  nativeBuildInputs = [autoPatchelfHook];
  buildInputs = [stdenv.cc.cc.lib];

  # The release archive is a flat bundle whose only useful artifact is the
  # root-level ELF binary. Extract it explicitly instead of relying on the
  # generic unpacker, which rejects this archive layout.
  unpackPhase = ''
    tar -xzf "$src"
  '';

  installPhase = ''
    install -Dm755 ./peakminer "$out/bin/peakminer"
  '';

  meta = {
    description = "Kryptex's GPU miner for Pearl (PRL)";
    homepage = "https://github.com/kryptex-miners-org/kryptex-miners/releases";
    license = lib.licenses.unfree;
    mainProgram = "peakminer";
    platforms = lib.platforms.linux;
  };
}

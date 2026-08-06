{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  ...
}:
stdenv.mkDerivation {
  pname = "peakminer";
  version = "2.8.0";

  src = fetchurl {
    url = "https://github.com/kryptex-miners-org/kryptex-miners/releases/download/peakminer-2-8-0/peakminer-2.8.0.tar.gz";
    hash = "sha256-miytzJcTZuwWUsAtu4CW54LVZB576J3SA3fC5dn0/M4=";
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

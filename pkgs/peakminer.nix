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

  installPhase = ''
    install -Dm755 peakminer $out/bin/peakminer
  '';

  meta = {
    description = "Kryptex's GPU miner for Pearl (PRL)";
    homepage = "https://github.com/kryptex-miners-org/kryptex-miners/releases";
    license = lib.licenses.unfree;
    mainProgram = "peakminer";
    platforms = lib.platforms.linux;
  };
}

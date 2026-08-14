{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  ...
}:
stdenv.mkDerivation {
  pname = "peakminer";
  version = "2.9.1";

  src = fetchurl {
    url = "https://github.com/peakminer/peakminer/releases/download/v2.9.1/peakminer-2.9.1.tar.gz";
    hash = "sha256-SuTR2J8mlw5JlwGBobD03qeVDusR/vWSjZQINgGABpw=";
  };

  nativeBuildInputs = [autoPatchelfHook];
  buildInputs = [stdenv.cc.cc.lib];

  # The release archive wraps the binary in a `peakminer/` dir (layout changed
  # at 2.9.1; 2.9.0 and earlier shipped it at the archive root). Extract the
  # whole archive then install from the nested path so the generic unpacker
  # doesn't fight us.
  unpackPhase = ''
    tar -xzf "$src"
  '';

  installPhase = ''
    install -Dm755 ./peakminer/peakminer "$out/bin/peakminer"
  '';

  meta = {
    description = "Kryptex's GPU miner for Pearl (PRL)";
    homepage = "https://github.com/peakminer/peakminer/releases";
    license = lib.licenses.unfree;
    mainProgram = "peakminer";
    platforms = lib.platforms.linux;
  };
}

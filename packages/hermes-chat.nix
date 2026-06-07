{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
  fontconfig,
  wayland,
  libxkbcommon,
  makeWrapper,
}:
rustPlatform.buildRustPackage rec {
  pname = "hermes-chat";
  version = "0.1.0-unstable";

  src = fetchFromGitHub {
    owner = "tuxclaw";
    repo = "hermes-chat";
    rev = "3f62170c6e21bdffbba5a592d4fa8234cba81f9c";
    hash = "sha256-IleO4enxHDWWGU2jWerPQVGx5osfB02tYoejl8FmQ/k=";
  };

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
    allowBuiltinFetchGit = true;
  };

  nativeBuildInputs = [pkg-config makeWrapper];
  buildInputs = [wayland libxkbcommon openssl fontconfig];

  buildNoBuildCargoCheck = true;

  postFixup = ''
    wrapProgram $out/bin/hermes-chat \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath buildInputs}"
  '';

  meta = with lib; {
    description = "Native Rust desktop chat client for Hermes Agent";
    homepage = "https://github.com/tuxclaw/hermes-chat";
    license = licenses.mit;
    mainProgram = "hermes-chat";
    platforms = platforms.linux;
    maintainers = [];
  };
}

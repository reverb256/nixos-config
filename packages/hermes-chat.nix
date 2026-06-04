{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
  fontconfig,
  git,
  wayland,
  libxkbcommon,
  xorg,
  libGL,
  vulkan-loader,
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

  nativeBuildInputs = [pkg-config git makeWrapper];
  buildInputs = [openssl fontconfig wayland libxkbcommon xorg.libX11 xorg.libXcursor xorg.libXi xorg.libXrandr libGL vulkan-loader];

  buildNoBuildCargoCheck = true;
  postFixup = ''
    wrapProgram $out/bin/hermes-chat \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath buildInputs}"
  '';

  # Use LTO and strip like upstream
  CARGO_PROFILE_RELEASE_LTO = "thin";
  CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "1";
  CARGO_PROFILE_RELEASE_STRIP = "true";

  # Post-install: add to path
  postInstall = ''
        mkdir -p $out/share/applications
        cat > $out/share/applications/hermes-chat.desktop <<EOF
    [Desktop Entry]
    Name=Hermes Chat
    Comment=Native desktop client for Hermes Agent
    Exec=$out/bin/hermes-chat
    Icon=hermes-chat
    Terminal=false
    Type=Application
    Categories=Network;InstantMessaging;
    EOF
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

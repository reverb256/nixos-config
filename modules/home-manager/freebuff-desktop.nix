{ lib, pkgs, ... }:
let
  # Freebuff Desktop shortcut (Layer 2: declarative .desktop only).
  #
  # The Freebuff *binary* lives in Layer 3 (nix profile) per issue #338
  # (`nix profile install reverb256/freebuff-flake#packages.x86_64-linux.default`
  # → ~/.nix-profile/bin/freebuff-desktop). This module generates ONLY the
  # launcher entry so it appears in niri/rofi/anyrun. Exec points at the
  # Layer-3 binary on PATH — do NOT rebuild/install the binary here, or the
  # HM `nix profile install` collides with the Layer-3 entry (both provide
  # bin/freebuff-desktop at priority 5).
  #
  # Icon: name-based so the DE resolves it if a theme provides one and
  # falls back gracefully otherwise. The Layer-3 freebuff package does not
  # currently ship its icon in $out/share (AppImage extraction is a no-op
  # there), so we avoid a broken absolute path. Fixing the icon belongs in
  # the Layer-3 package definition, not here.
  desktopFile = pkgs.writeText "freebuff.desktop" ''
    [Desktop Entry]
    Name=Freebuff
    GenericName=Coding Agent Orchestrator
    Comment=Freebuff Desktop — GitHub-native coding-agent orchestrator
    Exec=freebuff-desktop --no-sandbox --disable-gpu-sandbox %U
    Icon=freebuff
    Terminal=false
    Type=Application
    Categories=Development;Utility;
    StartupWMClass=Freebuff
  '';
in {
  # Declarative .desktop launcher for Freebuff Desktop, shown in the
  # app launcher (niri/rofi/anyrun). Binary comes from Layer 3 (nix profile).
  xdg.dataFile."applications/freebuff.desktop".source = desktopFile;
}

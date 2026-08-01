{ lib, ... }:
{
  # Hermes Desktop (Electron companion GUI) is installed via
  # `nix profile install github:NousResearch/hermes-agent#packages.x86_64-linux.desktop`
  # into ~/.nix-profile/bin/hermes-desktop. The upstream package ships NO
  # .desktop file, so it never appears in the launcher (Noctalia / app picker).
  #
  # The 2026-07-31 mime-fix.nix generalization (auto-symlink every nix-profile
  # .desktop) was developed in a worktree and never merged, so hermes-desktop
  # was invisible. Generate the entry via xdg.dataFile (same proven mechanism
  # as tui-apps.nix / freebuff-desktop.nix) — HM translates it into
  # ~/.local/share/applications/hermes-desktop.desktop on activation. Binary is
  # on PATH; icon is the package's own PNG via the nix-profile symlink (stable
  # while hermes-desktop stays installed).
  xdg.dataFile."applications/hermes-desktop.desktop".text = ''
    [Desktop Entry]
    Version=1.0
    Name=Hermes Desktop
    GenericName=Hermes Agent Companion
    Comment=Hermes Agent desktop companion (Electron)
    Exec=hermes-desktop %U
    Icon=/home/j_kro/.nix-profile/share/hermes-desktop/dist/hermes.png
    Terminal=false
    Type=Application
    Categories=Utility;Chat;Office;
    Keywords=hermes;agent;ai;chat;
    StartupNotify=false
  '';
}

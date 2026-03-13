# Gamescope Session Script for Nexus
# Auto-launch Steam in Gamescope on tty3
{
  lib,
  pkgs,
  ...
}: let
  # Create the gamescope-session wrapper script
  gamescopeSession = pkgs.writeShellScriptBin "gamescope-session" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Gamescope configuration for RTX 3060 Ti
    # Adjust resolution/refresh rate for your monitor
    # STEAM_GAMESCOPE_VRR_SUPPORTED=1 enables VRR
    # STEAM_MULTIPLE_XWAYLANDS=1 for proper keyboard/mouse support

    export STEAM_GAMESCOPE_VRR_SUPPORTED=1
    export STEAM_MULTIPLE_XWAYLANDS=1

    # Start gamescope with MangoHud support
    # --mangoapp enables MangoHud control from within Steam
    # -W -H -r: resolution and refresh rate
    # -O: output display (check with 'wayland-info' or 'wlr-randr')
    exec ${pkgs.gamescope}/bin/gamescope \
      --mangoapp \
      -W 1920 \
      -H 1080 \
      -r 165 \
      -O DP-1 \
      -e \
      --xwayland-count 2 \
      -- steam -steamdeck -steamos3
  '';
in {
  environment = {
    systemPackages = with pkgs; [
      gamescopeSession
      gamescope
      steam
      mangohud
      # gamescopectl  # TODO: Not packaged in nixpkgs yet
    ];
  };

  # Auto-login configuration for tty3 (Gamescope session)
  # The -o flag to agetty prevents auto-login, -f -p enables it for specific user
  systemd.services."getty@tty3" = {
    overrideStrategy = "asDropin";

    serviceConfig = {
      ExecStart = lib.mkForce [
        "/run/current-system/sw/bin/agetty"
        "--autologin"
        "j_kro"
        "--noclear"
        "tty3"
        "linux"
      ];
      Restart = "no";
    };
  };

  # Create bash_profile that auto-starts gamescope on tty3
  environment.etc."bash-profile.d/gamescope-tty3".text = ''
    # Auto-start gamescope when logging into tty3
    if [[ $(tty) == "/dev/tty3" ]]; then
      # Start gamescope session
      exec ${gamescopeSession}/bin/gamescope-session
    fi
  '';

  # Helper aliases for switching between sessions
  environment.etc."bashrc.d/gamescope-aliases".text = ''
    # Gamescope aliases for Nexus
    alias desktop='chvt 2'  # Switch to Plasma on tty2
    alias gamescope='chvt 3'  # Switch to Gamescope on tty3
    alias gsteam="exec ${gamescopeSession}/bin/gamescope-session"
  '';
}

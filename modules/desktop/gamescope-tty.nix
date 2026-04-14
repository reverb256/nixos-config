{
  lib,
  pkgs,
  ...
}: let
  gamescopeSession = pkgs.writeShellScriptBin "gamescope-session" ''
    #!/usr/bin/env bash
    set -euo pipefail


    export STEAM_GAMESCOPE_VRR_SUPPORTED=1
    export STEAM_MULTIPLE_XWAYLANDS=1

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
    ];
  };

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

  environment.etc."bash-profile.d/gamescope-tty3".text = ''
    if [[ $(tty) == "/dev/tty3" ]]; then
      exec ${gamescopeSession}/bin/gamescope-session
    fi
  '';

  environment.etc."bashrc.d/gamescope-aliases".text = ''
    alias desktop='chvt 2'
    alias gamescope='chvt 3'
    alias gsteam="exec ${gamescopeSession}/bin/gamescope-session"
  '';
}

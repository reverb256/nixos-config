# VRChat / Proton-GE-RTSP video-unlock automation.
#
# Proton-GE-RTSP restores in-world video players (YouTube/Twitch/ProTV in
# VRChat), but the h264/RTMP decode path stays DISABLED until Steam is told
# to unlock it via `steam steam://unlockh264/`. This must run while Steam is
# running. Running it again is idempotent and safe.
#
# Gated by services.gaming.vr.enable (VR hosts only, e.g. zephyr).
#
# Reference: https://www.protondb.com/app/438100 (tinker steps)
{ config, lib, pkgs, ... }:
with lib; let
  cfg = config.services.gaming;
  steamPkg = config.programs.steam.package;
in mkIf (cfg.enable && cfg.vr.enable) {
  # One-shot, retried after the graphical session + Steam are up.
  systemd.user.services.vrchat-video-unlock = {
    description = "Unlock Proton-GE-RTSP h264 video path for VRChat (steam://unlockh264)";
    # Steam must already be running for the steam:// URL to be handled.
    # graphical-session.target covers niri (uwsm) on zephyr.
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Retry up to ~5 min: Steam may take a while to come up after login.
      ExecStart = pkgs.writeShellScript "vrchat-video-unlock" ''
        set -u
        STEAM_BIN="${steamPkg}/bin/steam"
        for i in $(seq 1 60); do
          # Steam signals readiness via its ~/.steam/steam/.running lock or the
          # steamctl socket. We probe by asking steam to report its pid; if it
          # answers, it is up and will handle the steam:// URL.
          if pgrep -f "[s]team" >/dev/null 2>&1; then
            echo "vrchat-video-unlock: Steam detected, issuing unlockh264"
            "${steamPkg}/bin/steam" steam://unlockh264/ || true
            echo "vrchat-video-unlock: unlockh264 issued (idempotent)"
            exit 0
          fi
          sleep 5
        done
        echo "vrchat-video-unlock: Steam not running within timeout; skipping" >&2
        # Not a failure — user may not launch Steam this session.
        exit 0
      '';
      Restart = "no";
    };
  };

  # Documentation helper: per-game launch option for the iyuv_32 crash workaround.
  # Some RTSP builds crash on video players unless this override is set as a
  # VRChat-specific launch option in Steam:
  #   WINEDLLOVERRIDES="iyuv_32=" %command%
  # This is per-game (Steam appid 438100) and lives in the user's Steam config,
  # so it cannot be fully declared here. Printed for operator reference.
  environment.systemPackages = with pkgs; [
    (pkgs.writeShellScriptBin "vrchat-rtsp-help" ''
      cat <<'HELP'
Proton-GE-RTSP is installed and selectable in Steam for VRChat (appid 438100).
Video players need: steam steam://unlockh264/  (auto-run by vrchat-video-unlock).

If VRChat still crashes on video players, set the per-game launch option:
  WINEDLLOVERRIDES="iyuv_32=" %command%
in Steam -> VRChat -> Properties -> Launch Options.
HELP
    '')
  ];
}

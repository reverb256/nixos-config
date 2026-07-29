# Niri spawn-at-startup apps (polkit agent, noctalia daemon, ckb-next).
# Extracted from modules/home-manager/niri-config.nix on 2026-07-29
# per audit F-22 (de-monolith niri-config.nix mega-module).
#
# Notes:
#   - noctalia runs as a niri spawn child (NOT a detached systemd
#     user service) because logind GetSessionByPID doesn't resolve
#     user-service PIDs. The spawn-at-startup scope puts it in
#     session-*.scope, so DDC/CI and SDR brightness work.
#   - `noctaliaPackage` is injected via home-manager.nix extraSpecialArgs
#     (the NixOS-wrapped binary with PortAudio LD_LIBRARY_PATH).
#   - Clipboard monitoring moved to CopyQ (see modules/home-manager/copyq.nix).
{ config, lib, pkgs, noctaliaPackage, ... }:
let niriHmAvailable = config.lib ? niri;
in lib.mkIf niriHmAvailable {
  programs.niri.settings = {
    spawn-at-startup = [
      {
        argv = [
          "uwsm"
          "finalize"
        ];
      }
      {
        argv = [
          "uwsm"
          "app"
          "-s"
          "s"
          "--"
          "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
        ];
      }
      # 2026-07-10: noctalia daemon moved BACK into spawn-at-startup.
      # It was previously a detached `systemd --user` service, but
      # BrightnessService resolves controllable displays via logind
      # GetSessionByPID, which returns NoSessionForPID for user-service
      # PIDs — so brightness probing aborted and all sliders grayed out.
      # Running as a niri spawn child puts it in session-*.scope (niri's
      # scope), so logind resolves and DDC/CI + SDR brightness work.
      # niri respawns failed spawn-at-startup apps (restart-on-failure).
      {
        argv = [
          "uwsm"
          "app"
          "-s"
          "s"
          "--"
          "${noctaliaPackage}/bin/noctalia"
        ];
      }
      {
        argv = [
          "uwsm"
          "app"
          "-s"
          "b"
          "--"
          "ckb-next"
          "-b"
        ];
      }
      # Clipboard monitoring moved to CopyQ (home-manager module)
    ];
  };
}

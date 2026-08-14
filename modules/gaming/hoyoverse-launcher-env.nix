# Anime launcher (aagl) environment fix — zephyr.
#
# Two env bugs poison the aagl launchers' wine spawns:
#
# 1. STALE VK_DRIVER_FILES — the launcher inherits the process env of
#    whatever launched it. On a long-lived niri session that is
#    VK_DRIVER_FILES=/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json,
#    which does NOT exist (the real ICD is the nix-managed /etc/xdg link,
#    see hosts/zephyr/configuration.nix + nvidia-common.nix). Every Vulkan
#    process then dies with "Found no drivers" — Genshin/HSR silently exit
#    ~10s after launch, no window ever appears.
#
# 2. GLOBAL ENABLE_GAMESCOPE_WSI — gaming-base.nix exports
#    ENABLE_GAMESCOPE_WSI=1 (gated by services.gaming.hdr.enable, on for
#    zephyr) so the gamescope WSI layer loads in EVERY Vulkan process.
#    But the aagl wine games run where gamescope is NOT active, so the
#    layer's swapchain hook fails with a modal:
#      "CreateSwapchainKHR: Creating swapchain for non-Gamescope
#       swapchain. Hooking has failed somewhere! You may have a bad
#       Vulkan layer interfering."
#    Unset it for the launchers (they are not gamescope sessions).
#
# The session variable only fixes NEW sessions. These wrappers export the
# correct path before exec so the launcher process (and every wine it
# spawns) gets the right env regardless of when the session started.
#
# Dependency on the aagl flake module is safe: this file only overrides
# `programs.<launcher>.package`, which the aagl module defines.

{ config, lib, pkgs, ... }:

let
  icdPath = "/etc/xdg/vulkan/icd.d/nvidia_icd.json";

  # Wrap an aagl launcher package so it always exports the correct
  # NVIDIA Vulkan ICD and drops the gamescope WSI layer before exec.
  # The original package is the symlinkJoin with the steam-run wrapper;
  # we wrap THAT, so the exported env flows through steam-run →
  # launcher → wine → game.
  wrapLauncherEnv = launcherPkg: pkgs.writeShellScriptBin launcherPkg.pname ''
    export VK_DRIVER_FILES=${icdPath}
    unset ENABLE_GAMESCOPE_WSI DXVK_HDR PROTON_ENABLE_HDR
    exec ${launcherPkg}/bin/${launcherPkg.pname} "$@"
  '';
in
{
  # aagl launcher options only exist on hosts importing the aagl flake module
  # (zephyr desktop). `config ? programs.anime-game-launcher` short-circuits so
  # nexus/sentry/forge (no aagl module) eval without the package lookup.
  # Regression: 2026-08-14 p1/p3 commit referenced pkgs.anime-game-launcher
  # unconditionally -> every host eval failed "attribute 'anime-game-launcher'
  # missing". mkIf on a NON-EXISTENT option still errors — must gate the option
  # presence, not just `enable or false`.
  config = lib.mkMerge [
    (lib.mkIf (config ? programs.anime-game-launcher && config.programs.anime-game-launcher.enable or false) {
      programs.anime-game-launcher.package = wrapLauncherEnv pkgs.anime-game-launcher;
    })
    (lib.mkIf (config ? programs.honkers-railway-launcher && config.programs.honkers-railway-launcher.enable or false) {
      programs.honkers-railway-launcher.package = wrapLauncherEnv pkgs.honkers-railway-launcher;
    })
  ];
}

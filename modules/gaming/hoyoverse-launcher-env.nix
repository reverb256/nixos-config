# Anime launcher (aagl) environment fix — zephyr.
#
# The aagl flake (ezKEa/aagl-gtk-on-nix) wraps every launcher in its own
# steam-run FHS env. The launchers then spawn wine with the process env
# they inherited — which on a long-lived niri session is STALE:
#
#   VK_DRIVER_FILES=/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json
#
# That path does NOT exist on this system (the real ICD is the nix-managed
# /etc/xdg link, see hosts/zephyr/configuration.nix + nvidia-common.nix).
# Every Vulkan process then dies with "Found no drivers" — Genshin/HSR
# silently exit ~10s after launch, no window ever appears.
#
# The session variable only fixes NEW sessions. These wrappers export the
# correct path before exec so the launcher process (and every wine it
# spawns) gets the right ICD regardless of when the session started.
#
# Dependency on the aagl flake module is safe: this file only overrides
# `programs.<launcher>.package`, which the aagl module defines.

{ config, lib, pkgs, ... }:

let
  icdPath = "/etc/xdg/vulkan/icd.d/nvidia_icd.json";

  # Wrap an aagl launcher package so it always exports the correct
  # NVIDIA Vulkan ICD before exec. The original package is the
  # symlinkJoin with the steam-run wrapper; we wrap THAT, so the
  # exported env flows through steam-run → launcher → wine → game.
  wrapWithVulkanIcd = launcherPkg: pkgs.writeShellScriptBin launcherPkg.pname ''
    export VK_DRIVER_FILES=${icdPath}
    exec ${launcherPkg}/bin/${launcherPkg.pname} "$@"
  '';
in
{
  config = lib.mkMerge [
    (lib.mkIf (config.programs.anime-game-launcher.enable or false) {
      programs.anime-game-launcher.package = wrapWithVulkanIcd pkgs.anime-game-launcher;
    })
    (lib.mkIf (config.programs.honkers-railway-launcher.enable or false) {
      programs.honkers-railway-launcher.package = wrapWithVulkanIcd pkgs.honkers-railway-launcher;
    })
  ];
}

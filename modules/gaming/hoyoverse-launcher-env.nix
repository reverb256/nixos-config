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
{
  config,
  lib,
  pkgs,
  ...
}: let
  # 2026-08-15: NO VK_DRIVER_FILES here anymore. The steam-run FHS rootfs
  # in the current nixpkgs ships the NVIDIA ICD at the standard
  # /usr/share/vulkan/icd.d/nvidia_icd.json (verified present in the current
  # gen's steam-run-1.0.0.87-fhsenv-rootfs). Setting VK_DRIVER_FILES was a
  # band-aid for the launcher running a STALE rootfs (pre-deploy), and it
  # actively broke when the sandbox mounted its own /etc/xdg (no vulkan dir)
  # -> loader found no driver -> DXVK 'vkCreateInstance res=-9'. The loader
  # finds the ICD normally inside the fixed FHS. If the ICD ever goes
  # missing, rebuild (nixos-rebuild) and RESTART the launcher — do not
  # re-add env hacks.
  # 2026-08-15 FUNDAMENTAL FIX: the aagl launcher builds its own custom FHS
  # (pkgs/wrapAAGL/fhsenv.nix) with vulkan-loader but NOT the NVIDIA driver,
  # so the sandbox lacks /usr/share/vulkan/icd.d/nvidia_icd.json and every
  # Vulkan game fails (DXVK 'vkCreateInstance res=-9'). The launcher package
  # accepts extraLibraries and passes it to the FHS multiPkgs; add the system
  # nvidia driver so the ICD + GL libs land at standard paths INSIDE the
  # sandbox and the loader finds them with NO env vars.
  nvidiaDrv = config.hardware.nvidia.package;

  withNvidiaLibraries = pkg:
    pkg.override {
      extraLibraries = pkgs: [nvidiaDrv];
    };

  # Wrap an aagl launcher package so it always exports the correct
  # NVIDIA Vulkan ICD and drops the gamescope WSI layer before exec.
  # The original package is the symlinkJoin with the steam-run wrapper;
  # we wrap THAT, so the exported env flows through steam-run →
  # launcher → wine → game.
  # IMPORTANT (2026-08-14 regression): a bare writeShellScriptBin drops the
  # original package's share/ tree, which carries the launcher .desktop
  # entries (and pixmap icons via the separate -icon output). That made the
  # desktop entries dangle in generations after commit 61882e092. Use
  # symlinkJoin to keep share/ intact while overriding bin/ with the
  # env-fixing wrapper.
  # Build the env-fixing wrapper AND regenerate the .desktop entries so
  # Exec= points at the wrapper (a symlinkJoin of the original package keeps
  # the original .desktop whose Exec= hits the UNWRAPPED binary — the env fix
  # would be silently bypassed on desktop launches, reproducing the original
  # gamescope/ICD bugs).
  # IMPORTANT (2026-08-14): NEVER run the launcher itself inside gamescope.
  # gamescope cannot work inside the launcher's bwrap sandbox (capability
  # failure: "failed to inherit capabilities: Operation not permitted") and
  # the WSI layer poisons every Vulkan process when gamescope is not
  # actually compositing. The launcher is a GTK app that must open as a
  # normal niri window; only the GAME (wine64 child) is a candidate for
  # gamescope, and it is NOT wrapped here. Regression ab39b63b wrapped the
  # launcher in gamescope when services.gaming.hdr.enable was on, which
  # trapped the launcher window in a gamescope session and re-broke Vulkan
  # for the game.
  wrapLauncherEnv = launcherPkg: let
    wrapper = pkgs.writeShellScriptBin launcherPkg.pname ''
      unset ENABLE_GAMESCOPE_WSI DXVK_HDR PROTON_ENABLE_HDR
      exec ${launcherPkg}/bin/${launcherPkg.pname} "$@"
    '';
    # Reuse the original package's desktop entry and icon data, but rewrite
    # Exec= to point at the env-fixing wrapper so desktop launches get the
    # fix. Original .desktop lives at share/applications/<pname>.desktop;
    # the icon/name fields are read from it rather than guessed from meta.
    desktopSrc = launcherPkg + "/share/applications/" + launcherPkg.pname + ".desktop";
    desktopName = launcherPkg.pname + "-wrapped";
  in
    pkgs.runCommand desktopName {} ''
      mkdir -p $out/bin $out/share/applications
      ln -s ${wrapper}/bin/${launcherPkg.pname} $out/bin/${launcherPkg.pname}
      # Copy ALL share data (pixmaps, icons, etc.) from the original package.
      # -L dereferences symlinks: the store share/ tree uses symlinks to the
      # -icon/.desktop outputs; copying them as symlinks leaves read-only
      # store targets that the awk rewrite below cannot overwrite.
      cp -rL ${launcherPkg}/share/* $out/share/ 2>/dev/null || true
      # Regenerate the desktop file with Exec= pointed at the wrapper,
      # preserving the original Name/Icon fields. Remove the copied file
      # first — cp -rL preserves the store's read-only mode (444), so a
      # shell redirect onto it fails with Permission denied.
      if [ -f ${desktopSrc} ]; then
        rm -f $out/share/applications/${launcherPkg.pname}.desktop
        ${pkgs.gawk}/bin/awk -v exe="${wrapper}/bin/${launcherPkg.pname}" '
          /^Exec=/ { print "Exec=" exe; next }
          { print }
        ' ${desktopSrc} > $out/share/applications/${launcherPkg.pname}.desktop
      else
        echo "WARNING: no original .desktop for ${launcherPkg.pname}" >&2
      fi
    '';
in {
  # aagl launcher options only exist on hosts importing the aagl flake module
  # (zephyr desktop). `config ? programs.anime-game-launcher` short-circuits so
  # nexus/sentry/forge (no aagl module) eval without the package lookup.
  # Regression: 2026-08-14 p1/p3 commit referenced pkgs.anime-game-launcher
  # unconditionally -> every host eval failed "attribute 'anime-game-launcher'
  # missing". mkIf on a NON-EXISTENT option still errors — must gate the option
  # presence, not just `enable or false`.
  config = lib.mkMerge [
    (lib.mkIf (config ? programs.anime-game-launcher && config.programs.anime-game-launcher.enable or false) {
      programs.anime-game-launcher.package = wrapLauncherEnv (withNvidiaLibraries pkgs.anime-game-launcher);
    })
    (lib.mkIf (config ? programs.honkers-railway-launcher && config.programs.honkers-railway-launcher.enable or false) {
      programs.honkers-railway-launcher.package = wrapLauncherEnv (withNvidiaLibraries pkgs.honkers-railway-launcher);
    })
  ];
}

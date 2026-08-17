# aagl (ezKEa/aagl-gtk-on-nix) — ALL configuration for the aagl
# anime launchers lives here. One module, one program (the aagl
# launcher family). Do NOT spread aagl config into other modules.
#
# Covers:
#   1. Flake-level settings (release-branch check).
#   2. Launcher package wrapping: NVIDIA Vulkan ICD into the FHS
#      sandbox, gamescope WSI removal, and the wine sync enforcement
#      (FSync deadlock fix, 2026-08-16).
#
# The launchers (anime-game-launcher, honkers-railway-launcher,
# sleepy-launcher, wavey-launcher) are all provided by the aagl flake
# (inputs.aagl.nixosModules.default imported in desktop-modules.nix)
# and share the anime-launcher-sdk config schema.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # aagl (Gtk app wrapper) tracks its own 26.11 release branch while we stay on
  # Nixpkgs 26.05. The branch-mismatch check is a warning; we intentionally run
  # aagl ahead of Nixpkgs, so disable the check rather than chase a matching
  # aagl release that may not be published for 26.05.
  #
  # 2026-08-16 LAUNCHER WRAPPING: the launcher binaries are wrapped here so the
  # env + sync fixes reach the wine child processes. Two env bugs poison the
  # aagl launchers' wine spawns:
  #
  # 1. STALE VK_DRIVER_FILES — the launcher inherits the process env of
  #    whatever launched it. On a long-lived niri session that is
  #    VK_DRIVER_FILES=/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json,
  #    which does NOT exist (the real ICD is the nix-managed /etc/xdg link).
  #    Every Vulkan process then dies with "Found no drivers" — the games
  #    silently exit ~10s after launch, no window ever appears.
  #
  # 2. GLOBAL ENABLE_GAMESCOPE_WSI — gaming-base.nix exports
  #    ENABLE_GAMESCOPE_WSI=1 (gated by services.gaming.hdr.enable, on for
  #    zephyr) so the gamescope WSI layer loads in EVERY Vulkan process.
  #    But the aagl wine games run where gamescope is NOT active, so the
  #    layer's swapchain hook fails with a modal. Unset it for the launchers.
  #
  # The session variable only fixes NEW sessions. These wrappers export the
  # correct path before exec so the launcher process (and every wine it
  # spawns) gets the right env regardless of when the session started.

  # 2026-08-15: NO VK_DRIVER_FILES here anymore. The steam-run FHS rootfs
  # in the current nixpkgs ships the NVIDIA ICD at the standard
  # /usr/share/vulkan/icd.d/nvidia_icd.json (verified present in the current
  # gen's steam-run-1.0.0.87-fhsenv-rootfs). Setting VK_DRIVER_FILES was a
  # band-aid for the launcher running a STALE rootfs (pre-deploy), and it
  # actively broke when the sandbox mounted its own /etc/xdg (no vulkan dir)
  # -> loader found no driver -> DXVK 'vkCreateInstance res=-9'. The loader
  # finds the driver normally inside the fixed FHS, with no env vars.
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

  # Sync-enforcement snippet shared by every launcher wrapper. Patches
  # `~/.local/share/<launcher>/config.json` (anime-launcher-sdk schema):
  #   - game.wine.sync = "Off"   (drop FSync/ESync, the deadlock source)
  #   - game.environment: remove WINEFSYNC (kills the FSync+WINEFSYNC=0
  #     contradiction that left esync active at LoadNewScene)
  # The launcher reads config.json at startup; patching before exec means
  # every launch starts from the known-good sync state. Idempotent: no-op
  # when the file is already correct or missing (launcher first-run writes
  # its own defaults, which land as sync=Off AFTER this patch is moot — the
  # SDK default FSync is corrected on the very next launch).
  syncFix = ''
    CONFIG_FILE="$HOME/.local/share/__LAUNCHER__/config.json"
    if [ -f "$CONFIG_FILE" ]; then
      ${pkgs.python3}/bin/python3 - "$CONFIG_FILE" <<'PYEOF'
    import json, sys
    p = sys.argv[1]
    try:
        with open(p) as f:
            cfg = json.load(f)
    except (json.JSONDecodeError, OSError):
        sys.exit(0)  # corrupt/unreadable: leave for the launcher to repair
    wine = cfg.setdefault("game", {}).setdefault("wine", {})
    wine["sync"] = "Off"
    env = cfg.setdefault("game", {}).setdefault("environment", {})
    if isinstance(env, dict):
        env.pop("WINEFSYNC", None)
    with open(p, "w") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
    PYEOF
    fi
  '';

  # Wrap an aagl launcher package so it always exports the correct
  # NVIDIA Vulkan ICD, drops the gamescope WSI layer before exec, and
  # enforces the safe wine sync setting (see syncFix above).
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
      unset ENABLE_GAMESCOPE_WSI PROTON_ENABLE_HDR
      export DXVK_HDR=1
      # Enforce safe wine sync (2026-08-16). __LAUNCHER__ substituted below
      # because writeShellScriptBin does not interpolate $HOME at build time.
      ${builtins.replaceStrings ["__LAUNCHER__"] [launcherPkg.pname] syncFix}
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
  config = lib.mkMerge [
    # aagl (Gtk app wrapper) tracks its own 26.11 release branch while we
    # stay on Nixpkgs 26.05. The branch-mismatch check is a warning; we
    # intentionally run aagl ahead of Nixpkgs, so disable the check rather
    # than chase a matching aagl release that may not be published for 26.05.
    { aagl = { enableNixpkgsReleaseBranchCheck = false; }; }

    # aagl launcher options only exist on hosts importing the aagl flake
    # module (zephyr desktop). `config ? programs.anime-game-launcher`
    # short-circuits so nexus/sentry/forge (no aagl module) eval without
    # the package lookup. Regression: 2026-08-14 p1/p3 commit referenced
    # pkgs.anime-game-launcher unconditionally -> every host eval failed
    # "attribute 'anime-game-launcher' missing". mkIf on a NON-EXISTENT
    # option still errors — must gate the option presence, not just
    # `enable or false`.
    (lib.mkIf (config ? programs.anime-game-launcher && config.programs.anime-game-launcher.enable or false) {
      programs.anime-game-launcher.package = wrapLauncherEnv (withNvidiaLibraries pkgs.anime-game-launcher);
    })
    (lib.mkIf (config ? programs.honkers-railway-launcher && config.programs.honkers-railway-launcher.enable or false) {
      programs.honkers-railway-launcher.package = wrapLauncherEnv (withNvidiaLibraries pkgs.honkers-railway-launcher);
    })
    # 2026-08-16: sleepy-launcher (Sleepy) and wavey-launcher (Wuthering
    # Waves) are the SAME anime-launcher-sdk family — same config schema,
    # same FSync-default deadlock exposure. Wrap them identically.
    (lib.mkIf (config ? programs.sleepy-launcher && config.programs.sleepy-launcher.enable or false) {
      programs.sleepy-launcher.package = wrapLauncherEnv (withNvidiaLibraries pkgs.sleepy-launcher);
    })
    (lib.mkIf (config ? programs.wavey-launcher && config.programs.wavey-launcher.enable or false) {
      programs.wavey-launcher.package = wrapLauncherEnv (withNvidiaLibraries pkgs.wavey-launcher);
    })
  ];
}

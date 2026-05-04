{
  pkgs,
  config,
  lib,
  ...
}: let
  # Discord's runtime module downloader fails on NixOS (0-byte downloads).
  # This wrapper injects SKIP_MODULE_UPDATE=true into settings.json before
  # launch and seeds the versioned modules directory from an older version
  # so discord_desktop_core is available on first launch after a version bump.
  discord-patched = pkgs.discord.override {
    withOpenASAR = true;
    withVencord = true;
  };

  discord-modules-init = pkgs.writeShellScriptBin "discord-modules-init" ''
    set -euo pipefail

    settings="$HOME/.config/discord/settings.json"
    versioned_dir="$HOME/.config/discord/$(${pkgs.jq}/bin/jq -r .version ${discord-patched}/opt/Discord/resources/build_info.json)"
    modules_dir="$versioned_dir/modules"

    # Ensure SKIP_MODULE_UPDATE is set so Discord's broken module
    # downloader doesn't clobber seeded modules with 0-byte files.
    mkdir -p "$HOME/.config/discord"
    if [ -f "$settings" ]; then
      # Only write if the key is missing (avoid clobbering if Discord is mid-write)
      if ! ${pkgs.jq}/bin/jq -e '.SKIP_MODULE_UPDATE' "$settings" >/dev/null 2>&1; then
        ${pkgs.jq}/bin/jq '. + {"SKIP_MODULE_UPDATE": true}' "$settings" > "$settings.tmp" \
          && mv -f "$settings.tmp" "$settings"
      fi
    else
      echo '{"SKIP_MODULE_UPDATE":true}' > "$settings"
    fi

    # Seed discord_desktop_core if missing (e.g. after Nix package version bump).
    if [ ! -d "$modules_dir/discord_desktop_core" ]; then
      echo "[discord-modules-init] Seeding modules for $(basename "$versioned_dir")..."
      mkdir -p "$modules_dir"

      # Copy from any existing older version directory
      for old_dir in "$HOME/.config/discord"/[0-9]*; do
        [ -d "$old_dir/modules/discord_desktop_core" ] || continue
        [ "$old_dir" = "$versioned_dir" ] && continue
        echo "[discord-modules-init] Copying modules from $(basename "$old_dir")..."
        cp -rn "$old_dir/modules/discord_desktop_core" "$modules_dir/" 2>/dev/null || true
        break
      done

      if [ ! -d "$modules_dir/discord_desktop_core" ]; then
        echo "[discord-modules-init] WARNING: No older version found to seed from." >&2
        echo "[discord-modules-init] Discord may fail to start. Launch it once on a non-Nix system or" >&2
        echo "[discord-modules-init] restore discord_desktop_core from a backup." >&2
      fi
    fi
  '';
in {
  options.nixcord-config.enable = lib.mkEnableOption "Nixcord Discord configuration";

  config = lib.mkIf config.nixcord-config.enable {
    home.packages = [discord-patched discord-modules-init];

    programs.nixcord = {
      enable = true;
      discord.enable = false;
      vesktop.enable = false;

      config = {
        useQuickCss = true;
        plugins = {
          XSOverlay = {
            enable = true;
            dmNotifications = true;
            groupDmNotifications = true;
            serverNotifications = true;
            callNotifications = true;
            channelPingColor = "#8a2be2";
            pingColor = "#7289da";
            timeout = 3;
            volume = 0.2;
            opacity = 1.0;
          };
          fakeNitro = {
            enable = true;
            enableEmojiBypass = true;
            enableStickerBypass = true;
            enableStreamQualityBypass = true;
            emojiSize = 48.0;
          };
          USRBG = {
            enable = true;
            nitroFirst = true;
            voiceBackground = true;
          };
          ReviewDB = {
            enable = true;
          };
        };
      };
    };

    systemd.user.services.discord-autostart = {
      Unit = {
        Description = "Discord autostart";
        After = [
          "graphical-session-pre.target"
          "wayland-wm@niri-session.service"
        ];
        PartOf = ["graphical-session.target"];
      };
      Service = {
        Type = "simple";
        Environment = ["XDG_CURRENT_DESKTOP=KDE"];
        ExecStartPre = lib.getExe discord-modules-init;
        ExecStart = lib.getExe discord-patched + " --start-minimized";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install = {
        WantedBy = ["graphical-session.target"];
      };
    };
  };
}

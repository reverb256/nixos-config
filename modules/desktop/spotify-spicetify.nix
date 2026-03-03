{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.spotify-spicetify;
  stateDir = "/var/lib/spicetify";

  patchManagerScript = pkgs.writeShellScript "spicetify-patch-manager.sh" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    PATH="/run/current-system/sw/bin:$PATH"

    RED='\\033[0;31m'; GREEN='\\033[0;32m'; YELLOW='\\033[1;33m'; NC='\\033[0m'
    log() { echo -e "''${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]''${NC} $1"; }
    error() { echo -e "''${RED}[ERROR]''${NC} $1" >&2; }
    warn() { echo -e "''${YELLOW}[WARN]''${NC} $1"; }

    SPOTIFY_PATH="$(flatpak info com.spotify.Client --show-location 2>/dev/null)"
    SPOTIFY_DIR="''${SPOTIFY_PATH}/files/extra/share/spotify"
    BACKUP_DIR="${stateDir}/backups"
    VERSION_MARKER="${stateDir}/version"
    DISABLED_MARKER="${stateDir}/disabled"
    CONFIG_HASH="${stateDir}/config-applied"

    get_spotify_version() {
      flatpak info com.spotify.Client 2>/dev/null | grep "Version:" | awk '{print $2}' || echo "unknown"
    }

    is_patched() {
      [ -f "$VERSION_MARKER" ] && ${pkgs.flatpak}/bin/flatpak list | grep -q "com.spotify.Client"
    }

    apply_spicetify() {
      log "Starting Spicetify theming..."

      # Check if Spotify exists
      if [ ! -d "$SPOTIFY_DIR" ]; then
        error "Spotify directory not found at: $SPOTIFY_DIR"
        return 1
      fi

      # Check if SpotX is applied
      SPOTX_MARKER="$SPOTIFY_DIR/Apps/.spotx_patched"
      if [ ! -f "$SPOTX_MARKER" ]; then
        warn "SpotX not applied yet, waiting for spotx-patch.service"
        return 0
      fi

      local current_version=$(get_spotify_version)
      log "Spotify version: $current_version"

      # Check if already applied for this version
      if [ -f "$VERSION_MARKER" ]; then
        local patched_version=$(cat "$VERSION_MARKER" 2>/dev/null || echo "unknown")
        if [ "$patched_version" = "$current_version" ]; then
          log "Spicetify already applied for version $current_version"
          return 0
        fi
        log "Spotify updated from $patched_version to $current_version, re-applying..."
      fi

      # Stop Spotify
      log "Stopping Spotify..."
      flatpak kill com.spotify.Client 2>/dev/null || true

      # Backup
      local backup_name="backup-$(date +%Y%m%d-%H%M%S)"
      if [ -d "$SPOTIFY_DIR/Apps" ]; then
        mkdir -p "$BACKUP_DIR"
        cp -r "$SPOTIFY_DIR/Apps" "$BACKUP_DIR/$backup_name"
        log "Backup created: $backup_name"
      fi

      # Find user with Spotify installation
      local spotify_user=""
      for user_home in /home/*; do
        local user=$(basename "$user_home")
        if [ -d "$user_home/.var/app/com.spotify.Client" ]; then
          spotify_user="$user"
          break
        fi
      done

      if [ -z "$spotify_user" ]; then
        error "Could not find user with Spotify installed"
        return 1
      fi

      log "Running Spicetify as user: $spotify_user"

      # Apply Spicetify as the Spotify user (backup + apply)
      log "Applying Spicetify theme and extensions..."
      if su - "$spotify_user" -c "${pkgs.spicetify-cli}/bin/spicetify backup apply"; then
        echo "$current_version" > "$VERSION_MARKER"
        log "Spicetify applied successfully!"
        return 0
      else
        error "Spicetify application failed"
        return 1
      fi
    }

    disable_spicetify() {
      log "Disabling Spicetify..."
      echo "$1" > "$DISABLED_MARKER"
      systemctl disable spotify-spicetify.service
      systemctl stop spotify-spicetify.timer
      if ${pkgs.libnotify}/bin/notify-send "Spicetify" "Disabled due to error: $1" 2>/dev/null; then
        log "Desktop notification sent"
      fi
    }

    show_status() {
      if [ ! -f "$VERSION_MARKER" ]; then
        echo "Spicetify: not applied"
        return 1
      fi

      local current_version=$(get_spotify_version)
      local patched_version=$(cat "$VERSION_MARKER" 2>/dev/null || echo "unknown")

      if [ "$patched_version" = "$current_version" ]; then
        echo "Spicetify: applied (version: $current_version, theme: ${builtins.replaceStrings ["\""] [""] cfg.theme}/${cfg.colorScheme})"
        return 0
      else
        echo "Spicetify: version mismatch (patched: $patched_version, current: $current_version)"
        return 1
      fi
    }

    case "''${1:-apply}" in
      apply)
        if ! apply_spicetify; then
          if [ "${cfg.onFailure}" = "disable" ]; then
            disable_spicetify "Theme application failed"
          fi
          exit 1
        fi
        ;;
      status) show_status ;;
      disable) rm -f "$VERSION_MARKER" "$DISABLED_MARKER"; log "Spicetify disabled" ;;
      enable) rm -f "$DISABLED_MARKER"; log "Spicetify re-enabled" ;;
      *) echo "Usage: $0 {apply|status|disable|enable}"; exit 1 ;;
    esac
  '';

in {
  options.services.spotify-spicetify = {
    enable = mkEnableOption "Spotify theming and extensions via Spicetify";

    configPath = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to custom Spicetify config directory";
    };

    theme = mkOption {
      type = types.nullOr types.str;
      default = "Dribbblish";
      description = "Theme name to apply";
    };

    colorScheme = mkOption {
      type = types.str;
      default = "nord-dark";
      description = "Color scheme for theme";
    };

    customCSS = mkOption {
      type = types.lines;
      default = "";
      description = "Custom CSS to inject";
    };

    extensions = mkOption {
      type = types.listOf types.str;
      default = [ "adblock" "shuffle+" ];
      description = "List of extension names to enable";
    };

    customApps = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of custom apps to add";
    };

    autoApply = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically re-apply when Spotify updates";
    };

    checkInterval = mkOption {
      type = types.str;
      default = "daily";
      description = "How often to check and re-apply";
    };

    onFailure = mkOption {
      type = types.enum [ "disable" "notify-only" "ignore" ];
      default = "disable";
      description = "Behavior when Spicetify fails";
    };

    enableNotifications = mkOption {
      type = types.bool;
      default = true;
      description = "Send desktop notifications";
    };

    preApplyHook = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Script to run before applying";
    };

    postApplyHook = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Script to run after applying";
    };
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${stateDir} 0755 root root -"
      "d ${stateDir}/backups 0755 root root -"
    ];

    systemd.services.spotify-spicetify = {
      description = "Spotify Spicetify Theme Service";
      after = [ "spotx-patch.service" "network-online.target" ];
      wants = [ "spotx-patch.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${patchManagerScript} apply";
        StandardOutput = "journal";
        StandardError = "journal";
        User = "root";
        Group = "root";
      };
    };

    systemd.timers.spotify-spicetify = mkIf cfg.autoApply {
      description = "Spotify Spicetify Auto-Theme Timer";
      wantedBy = [ "timers.target" ];
      partOf = [ "spotify-spicetify.service" ];
      timerConfig = {
        OnCalendar = cfg.checkInterval;
        Unit = "spotify-spicetify.service";
        Persistent = true;
      };
    };

    systemd.services.spotify-spicetify-after-flatpak = mkIf config.services.flatpak.enable {
      description = "Run Spicetify after Flatpak updates";
      after = [ "flatpak-update.service" ];
      wants = [ "flatpak-update.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${patchManagerScript} apply";
        StandardOutput = "journal";
        StandardError = "journal";
        User = "root";
        Group = "root";
      };
    };

    environment.systemPackages = with pkgs; [
      (writeShellScriptBin "spotify-spicetify" ''
        #!${pkgs.bash}/bin/bash
        ${patchManagerScript} "$@"
      '')
    ];
  };
}
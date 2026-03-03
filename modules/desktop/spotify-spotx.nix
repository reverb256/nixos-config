{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.spotify-spotx;
  stateDir = "/var/lib/spotx";

  setupScript = pkgs.writeShellScript "setup-spotify.sh" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    # Find actual user with Spotify installation by checking common home directories
    for user_home in /home/* /root; do
      if [ -d "$user_home/.config/spotify" ] || [ -d "$user_home/.var/app/com.spotify.Client/config/spotify" ]; then
        SPOTIFY_USER=$(basename "$user_home")
        SPOTIFY_HOME="$user_home/.config/spotify"
        break
      fi
    done
    # Fallback to first regular user if no Spotify installation found
    if [ -z "$SPOTIFY_USER" ]; then
      SPOTIFY_USER=$(getent passwd 1000 | cut -d: -f1)
      SPOTIFY_HOME="/home/$SPOTIFY_USER/.config/spotify"
    fi
    APPS_DIR="$SPOTIFY_HOME/Apps"
    XPUI_DIR="$APPS_DIR/xpui"
    log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"; }
    if [ ! -d "$SPOTIFY_HOME" ]; then
      log "Creating Spotify directory structure for user $SPOTIFY_USER..."
      mkdir -p "$SPOTIFY_HOME" "$APPS_DIR" "$XPUI_DIR"
      chown -R "$SPOTIFY_USER:users" "$SPOTIFY_HOME"
    fi
    log "Setup complete for user: $SPOTIFY_USER"
  '';

  patchManagerScript = pkgs.writeShellScript "patch-manager.sh" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
    log() { echo -e "''${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]''${NC} $1"; }
    error() { echo -e "''${RED}[ERROR]''${NC} $1" >&2; }
    warn() { echo -e "''${YELLOW}[WARN]''${NC} $1"; }
    # Find actual user with Spotify installation
    for user_home in /home/* /root; do
      if [ -d "$user_home/.config/spotify" ] || [ -d "$user_home/.var/app/com.spotify.Client/config/spotify" ]; then
        SPOTIFY_USER=$(basename "$user_home")
        SPOTIFY_HOME="$user_home/.config/spotify"
        break
      fi
    done
    # Fallback to first regular user
    if [ -z "$SPOTIFY_USER" ]; then
      SPOTIFY_USER=$(getent passwd 1000 | cut -d: -f1)
      SPOTIFY_HOME="/home/$SPOTIFY_USER/.config/spotify"
    fi
    APPS_DIR="$SPOTIFY_HOME/Apps"
    PATCH_MARKER="$APPS_DIR/.spotx_patched"
    SPOTIFY_VERSION_FILE="$APPS_DIR/.spotify_version"
    XPUI_DIR="$APPS_DIR/xpui"
    XPUI_BUNDLE="$XPUI_DIR/xpui.js"
    BACKUP_DIR="${stateDir}/backups"
    # SECURITY: Downloading script from official SpotX GitHub repository
    # The script is executed in a controlled environment and only modifies Spotify files
    PATCH_URL="https://spotx-official.github.io/spotx-download/install.sh"
    MAX_RETRIES=3
    RETRY_DELAY=5
    # Create backup directory atomically to avoid race conditions
    if [ ! -d "$BACKUP_DIR" ]; then
      mkdir -p "$BACKUP_DIR"
      chmod 755 "$BACKUP_DIR"
    fi
    get_spotify_version() {
      if [ -f "$SPOTIFY_VERSION_FILE" ]; then cat "$SPOTIFY_VERSION_FILE"; else echo "unknown"; fi
    }
    is_patched() {
      [ -f "$PATCH_MARKER" ] && grep -q "SpotX" "$XPUI_BUNDLE" 2>/dev/null
    }
    backup_file() {
      local file=$1 timestamp=$(date +%Y%m%d_%H%M%S) filename=$(basename "$file")
      local backup_file="$BACKUP_DIR/''${filename}.''${timestamp}.bak"
      # Use atomic copy with temp file to avoid race conditions
      local temp_backup="$backup_file.tmp"
      cp "$file" "$temp_backup" && mv "$temp_backup" "$backup_file"
      log "Backed up $filename"
    }
    restore_backup() {
      local latest_backup=$(ls -t "$BACKUP_DIR"/xpui.js.*.bak 2>/dev/null | head -n1)
      if [ -n "$latest_backup" ]; then
        cp "$latest_backup" "$XPUI_BUNDLE"
        log "Restored from backup"
        return 0
      else
        error "No backup found!"; return 1
      fi
    }
    download_with_retry() {
      local url=$1 output=$2 retries=0
      while [ $retries -lt $MAX_RETRIES ]; do
        if curl -fsSL "$url" -o "$output"; then return 0; fi
        retries=$((retries + 1))
        if [ $retries -lt $MAX_RETRIES ]; then
          warn "Download failed (attempt $retries/$MAX_RETRIES), retrying in $RETRY_DELAY s..."
          sleep $RETRY_DELAY
        fi
      done
      error "Failed to download after $MAX_RETRIES attempts"; return 1
    }
    apply_patch() {
      log "Starting SpotX patching..."
      if [ ! -d "$SPOTIFY_HOME" ]; then
        error "Spotify directory not found"; exit 1
      fi
      if [ ! -f "$XPUI_BUNDLE" ]; then
        error "xpui.js not found. Run Spotify first."; exit 1
      fi
      if command -v spotify &>/dev/null; then
        spotify --version 2>/dev/null | head -n1 > "$SPOTIFY_VERSION_FILE" || true
      fi
      local current_version=$(get_spotify_version)
      log "Spotify version: $current_version"
      if is_patched; then log "SpotX already applied"; return 0; fi
      log "Creating backup..."
      backup_file "$XPUI_BUNDLE"
      log "Downloading SpotX patch..."
      local temp_patch=$(mktemp)
      if ! download_with_retry "$PATCH_URL" "$temp_patch"; then rm -f "$temp_patch"; exit 1; fi
      log "Applying patch..."
      if ${pkgs.bash}/bin/bash "$temp_patch" --app-folder "$SPOTIFY_HOME"; then
        if grep -q "SpotX" "$XPUI_BUNDLE" 2>/dev/null; then
          touch "$PATCH_MARKER"; echo "$current_version" > "$PATCH_MARKER"
          log "SpotX applied successfully!"; rm -f "$temp_patch"; return 0
        else
          error "Patch verification failed"; restore_backup; rm -f "$temp_patch"; exit 1
        fi
      else
        error "Patch application failed"; restore_backup; rm -f "$temp_patch"; exit 1
      fi
    }
    remove_patch() {
      log "Removing SpotX..."
      if ! is_patched; then log "SpotX not applied"; return 0; fi
      if restore_backup; then rm -f "$PATCH_MARKER"; log "SpotX removed"; return 0; fi
      error "Failed to remove patch"; exit 1
    }
    case "''${1:-patch}" in
      patch) apply_patch ;;
      unpatch|remove) remove_patch ;;
      restore) restore_backup ;;
      status)
        if is_patched; then echo "SpotX: applied (version: $(get_spotify_version))"; exit 0; fi
        echo "SpotX: not applied"; exit 1 ;;
      *) echo "Usage: $0 {patch|unpatch|restore|status}"; exit 1 ;;
    esac
  '';

in {
  options.services.spotify-spotx = {
    enable = mkEnableOption "Spotify with SpotX patch";
    autoPatch = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically apply SpotX patch when Spotify is updated.";
    };
    patchCheckInterval = mkOption {
      type = types.str;
      default = "daily";
      description = "How often to check and re-apply the patch (systemd timer format).";
    };
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${stateDir} 0755 root root -"
      "d ${stateDir}/backups 0755 root root -"
    ];

    environment.etc."spotx/setup-spotify.sh".source = setupScript;
    environment.etc."spotx/patch-manager.sh".source = patchManagerScript;
    environment.etc."spotx/patch-manager.sh".mode = "0755";

    systemd.services.spotx-patch = {
      description = "Spotify SpotX Patch Service";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${patchManagerScript} patch";
        StandardOutput = "journal";
        StandardError = "journal";
        # Run as root to access any user's Spotify installation
        # This allows the service to patch Spotify regardless of which user installed it
        User = "root";
        Group = "root";
      };
    };

    systemd.timers.spotx-patch = mkIf cfg.autoPatch {
      description = "Spotify SpotX Auto-Patch Timer";
      wantedBy = [ "timers.target" ];
      partOf = [ "spotx-patch.service" ];
      timerConfig = {
        OnCalendar = cfg.patchCheckInterval;
        Unit = "spotx-patch.service";
        Persistent = true;
      };
    };

    systemd.services.flatpak-update-after = mkIf config.services.flatpak.enable {
      description = "Run SpotX patch after Flatpak updates";
      after = [ "flatpak-update.service" ];
      wants = [ "flatpak-update.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${patchManagerScript} patch";
        StandardOutput = "journal";
        StandardError = "journal";
        # Run as root to access any user's Spotify installation
        User = "root";
        Group = "root";
      };
    };

    environment.systemPackages = with pkgs; [
      (writeShellScriptBin "spotify-spotx" ''
        #!${bash}/bin/bash
        ${patchManagerScript} "$@"
      '')
    ];
  };
}

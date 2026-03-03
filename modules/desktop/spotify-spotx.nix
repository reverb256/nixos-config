{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.spotify-spotx;

  # SpotX patch script
  spotxPatchScript = pkgs.writeShellScript "spotx-patch" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    # Color output
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color

    log() {
      echo -e "''${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]''${NC} $1"
    }

    error() {
      echo -e "''${RED}[ERROR]''${NC} $1" >&2
    }

    warn() {
      echo -e "''${YELLOW}[WARN]''${NC} $1"
    }

    # Configuration
    SPOTIFY_DIR="${cfg.spotifyDir}"
    APPS_DIR="$SPOTIFY_DIR/Apps"
    PATCH_MARKER="$APPS_DIR/.spotx_patched"
    SPOTIFY_VERSION_FILE="$APPS_DIR/.spotify_version"
    XPUI_DIR="$APPS_DIR/xpui"
    XPUI_BUNDLE="$XPUI_DIR/xpui.js"
    BACKUP_DIR="${cfg.backupDir}"
    PATCH_URL="${cfg.patchUrl}"

    # Ensure directories exist
    mkdir -p "$BACKUP_DIR"

    # Function to get current Spotify version
    get_spotify_version() {
      if [ -f "$SPOTIFY_VERSION_FILE" ]; then
        cat "$SPOTIFY_VERSION_FILE"
      else
        echo "unknown"
      fi
    }

    # Function to check if patch is already applied
    is_patched() {
      [ -f "$PATCH_MARKER" ] && grep -q "SpotX" "$XPUI_BUNDLE" 2>/dev/null
    }

    # Function to backup file
    backup_file() {
      local file=$1
      local timestamp=$(date +%Y%m%d_%H%M%S)
      local filename=$(basename "$file")
      cp "$file" "$BACKUP_DIR/''${filename}.''${timestamp}.bak"
      log "Backed up $filename to $BACKUP_DIR"
    }

    # Function to restore from backup
    restore_backup() {
      local latest_backup=$(ls -t "$BACKUP_DIR"/xpui.js.*.bak 2>/dev/null | head -n1)
      if [ -n "$latest_backup" ]; then
        cp "$latest_backup" "$XPUI_BUNDLE"
        log "Restored from backup: $latest_backup"
        return 0
      else
        error "No backup found!"
        return 1
      fi
    }

    # Function to download and apply patch
    apply_patch() {
      log "Starting SpotX patching process..."

      # Check if Spotify is installed
      if [ ! -d "$SPOTIFY_DIR" ]; then
        error "Spotify directory not found: $SPOTIFY_DIR"
        error "Please install Spotify first"
        exit 1
      fi

      # Check if xpui.js exists
      if [ ! -f "$XPUI_BUNDLE" ]; then
        error "xpui.js not found at: $XPUI_BUNDLE"
        error "Spotify may not be fully installed yet"
        exit 1
      fi

      # Store current version
      ${pkgs.spotify}/bin/spotify --version 2>/dev/null | head -n1 > "$SPOTIFY_VERSION_FILE" || true
      local current_version=$(get_spotify_version)
      log "Detected Spotify version: $current_version"

      # Check if already patched
      if is_patched; then
        log "SpotX is already applied"
        return 0
      fi

      # Create backup
      log "Creating backup of xpui.js..."
      backup_file "$XPUI_BUNDLE"

      # Download patch
      log "Downloading SpotX patch..."
      local temp_patch=$(mktemp)

      if ! curl -fsSL "$PATCH_URL" -o "$temp_patch"; then
        error "Failed to download patch from $PATCH_URL"
        rm -f "$temp_patch"
        exit 1
      fi

      # Apply patch
      log "Applying patch..."
      if ${pkgs.bash}/bin/bash "$temp_patch" --app-folder "$SPOTIFY_DIR"; then
        # Verify patch was applied
        if grep -q "SpotX" "$XPUI_BUNDLE" 2>/dev/null; then
          # Create marker
          touch "$PATCH_MARKER"
          echo "$current_version" > "$PATCH_MARKER"
          log "SpotX patch applied successfully!"
          rm -f "$temp_patch"
          return 0
        else
          error "Patch verification failed - SpotX signature not found"
          restore_backup
          rm -f "$temp_patch"
          exit 1
        fi
      else
        error "Patch application failed"
        restore_backup
        rm -f "$temp_patch"
        exit 1
      fi
    }

    # Function to remove patch
    remove_patch() {
      log "Removing SpotX patch..."

      if ! is_patched; then
        log "SpotX is not applied"
        return 0
      fi

      # Restore from backup
      if restore_backup; then
        rm -f "$PATCH_MARKER"
        log "SpotX patch removed successfully"
        return 0
      else
        error "Failed to remove patch"
        exit 1
      fi
    }

    # Main logic
    case "''${1:-patch}" in
      patch)
        apply_patch
        ;;
      unpatch|remove)
        remove_patch
        ;;
      restore)
        restore_backup
        ;;
      status)
        if is_patched; then
          echo "SpotX: applied (version: $(get_spotify_version))"
          exit 0
        else
          echo "SpotX: not applied"
          exit 1
        fi
        ;;
      *)
        echo "Usage: $0 {patch|unpatch|restore|status}"
        exit 1
        ;;
    esac
  '';

  # Setup script to prepare Spotify directory
  setupScript = pkgs.writeShellScript "spotify-spotx-setup" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    SPOTIFY_DIR="${cfg.spotifyDir}"
    APPS_DIR="$SPOTIFY_DIR/Apps"
    XPUI_DIR="$APPS_DIR/xpui"

    log() {
      echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    }

    # Ensure Spotify has been run at least once to create the directory structure
    if [ ! -d "$SPOTIFY_DIR" ]; then
      log "Creating Spotify directory structure..."
      mkdir -p "$SPOTIFY_DIR"
      mkdir -p "$APPS_DIR"
      mkdir -p "$XPUI_DIR"
    fi

    # Copy xpui.js from package if not present
    if [ ! -f "$XPUI_DIR/xpui.js" ] && [ -d "${pkgs.spotify}/share/spotify" ]; then
      log "Initializing xpui.js from package..."
      # This may not exist in all Spotify versions, so don't fail
      cp -r ${pkgs.spotify}/share/spotify/* "$SPOTIFY_DIR/" 2>/dev/null || true
    fi

    log "Setup complete"
  '';

in {
  options.services.spotify-spotx = {
    enable = mkEnableOption "Spotify with SpotX patch";

    user = mkOption {
      type = types.str;
      default = "root";
      description = "User account under which Spotify runs";
    };

    group = mkOption {
      type = types.str;
      default = "root";
      description = "Group under which Spotify runs";
    };

    autoPatch = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Automatically apply SpotX patch when Spotify is updated.
      '';
    };

    spotifyDir = mkOption {
      type = types.path;
      default = "\${HOME}/.config/spotify";
      example = "\${HOME}/.config/spotify";
      description = ''
        Directory where Spotify stores its data.
      '';
    };

    backupDir = mkOption {
      type = types.path;
      default = "\${HOME}/.config/spotify/backups";
      example = "\${HOME}/.config/spotify/backups";
      description = ''
        Directory to store backups of original files.
      '';
    };

    patchUrl = mkOption {
      type = types.str;
      default = "https://spotx-official.github.io/spotx-download/install.sh";
      description = ''
        URL to download the SpotX patch script from.
      '';
    };

    patchInterval = mkOption {
      type = types.str;
      default = "daily";
      description = ''
        How often to check and re-apply the patch (systemd timer format).
        Set to null to disable automatic re-patching.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Create tmpfiles entries for directories
    systemd.tmpfiles.rules = [
      "d ${cfg.spotifyDir} 0755 ${cfg.user} ${cfg.group} -"
      "d ${cfg.backupDir} 0755 ${cfg.user} ${cfg.group} -"
      "d ${cfg.spotifyDir}/Apps 0755 ${cfg.user} ${cfg.group} -"
      "d ${cfg.spotifyDir}/Apps/xpui 0755 ${cfg.user} ${cfg.group} -"
    ];

    # Setup service to prepare Spotify directory
    systemd.services.spotify-spotx-setup = {
      description = "Spotify SpotX Setup";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${setupScript}";
        RemainAfterExit = true;
      };
    };

    # Patch service
    systemd.services.spotify-spotx-patch = {
      description = "Spotify SpotX Patch Service";
      after = [ "spotify-spotx-setup.service" ];
      wants = [ "spotify-spotx-setup.service" ];

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${spotxPatchScript} patch";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    # Timer for automatic patching
    systemd.timers.spotify-spotx-patch = mkIf cfg.autoPatch {
      description = "Spotify SpotX Auto-Patch Timer";
      wantedBy = [ "timers.target" ];
      partOf = [ "spotify-spotx-patch.service" ];
      timerConfig = {
        OnCalendar = cfg.patchInterval;
        Unit = "spotify-spotx-patch.service";
        Persistent = true;
      };
    };

    # Add convenience aliases
    environment.systemPackages = mkIf cfg.enable (
      with pkgs; [
        (writeShellScriptBin "spotify-spotx" ''
          #!${bash}/bin/bash
          ${spotxPatchScript} "$@"
        '')
      ]
    );
  };

  meta = {
    maintainers = with maintainers; [ ];
    doc = ./README.md;
  };
}

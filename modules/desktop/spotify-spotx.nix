{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.spotify-spotx;
  stateDir = "/var/lib/spotx";

  setupScript = pkgs.writeShellScript "setup-spotify.sh" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    clr='\033[0m'
    red='\033[0;31m'
    green='\033[0;32m'

    log() { echo -e "''${green}[$(date +'%Y-%m-%d %H:%M:%S')]''${clr} $1"; }
    error() { echo -e "''${red}[ERROR]''${clr} $1" >&2; }

    log "=== Spotify + SpotX Initial Setup ==="

    # Ensure Flathub is available
    if ! ${pkgs.flatpak}/bin/flatpak remote-list | grep -q flathub; then
      error "Flathub remote not found. Enable Flatpak module first."
      exit 1
    fi

    # Install Spotify Flatpak if not present
    if ! ${pkgs.flatpak}/bin/flatpak list | grep -q "com.spotify.Client"; then
      log "Installing Spotify Flatpak from Flathub..."
      ${pkgs.flatpak}/bin/flatpak install -y flathub com.spotify.Client
    fi

    # Get Spotify Flatpak installation path
    SPOTIFY_PATH="$(${pkgs.flatpak}/bin/flatpak info com.spotify.Client --show-location 2>/dev/null)"
    SPOTIFY_DIR="''${SPOTIFY_PATH}/files/extra/share/spotify"

    if [ ! -d "$SPOTIFY_DIR" ]; then
      error "Spotify directory not found at: $SPOTIFY_DIR"
      exit 1
    fi

    # Apply SpotX-Bash patch (with -f flag to force re-patch if already installed)
    log "Applying SpotX-Bash patch for Spotify at $SPOTIFY_DIR..."
    if ${pkgs.bash}/bin/bash <(${pkgs.curl}/bin/curl -sSL https://raw.githubusercontent.com/SpotX-Official/SpotX-Bash/main/spotx.sh) -P "$SPOTIFY_DIR" -f; then
      log "✓ SpotX patch applied successfully!"
    else
      error "SpotX patch application failed"
      exit 1
    fi

    log "✓ Setup complete! Launch with: flatpak run com.spotify.Client"
  '';

  patchManagerScript = pkgs.writeShellScript "patch-manager.sh" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    # Include system packages for SpotX-Bash dependencies
    PATH="/run/current-system/sw/bin:$PATH"
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
    log() { echo -e "''${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]''${NC} $1"; }
    error() { echo -e "''${RED}[ERROR]''${NC} $1" >&2; }
    warn() { echo -e "''${YELLOW}[WARN]''${NC} $1"; }

    # Get Spotify Flatpak installation path
    SPOTIFY_PATH="$(flatpak info com.spotify.Client --show-location 2>/dev/null)"
    SPOTIFY_DIR="''${SPOTIFY_PATH}/files/extra/share/spotify"
    BACKUP_DIR="${stateDir}/backups"
    PATCH_MARKER="$SPOTIFY_DIR/Apps/.spotx_patched"

    # Create backup directory
    if [ ! -d "$BACKUP_DIR" ]; then
      mkdir -p "$BACKUP_DIR"
      chmod 755 "$BACKUP_DIR"
    fi

    get_spotify_version() {
      flatpak info com.spotify.Client 2>/dev/null | grep "Version:" | awk '{print $2}' || echo "unknown"
    }

    is_patched() {
      [ -f "$PATCH_MARKER" ] && ${pkgs.flatpak}/bin/flatpak list | grep -q "com.spotify.Client"
    }

    apply_patch() {
      log "Starting SpotX patching..."
      if [ ! -d "$SPOTIFY_DIR" ]; then
        error "Spotify directory not found at: $SPOTIFY_DIR"
        exit 1
      fi
      local current_version=$(get_spotify_version)
      log "Spotify version: $current_version"
      if [ -f "$PATCH_MARKER" ]; then
        local patched_version=$(cat "$PATCH_MARKER" 2>/dev/null || echo "unknown")
        if [ "$patched_version" = "$current_version" ]; then
          log "SpotX already applied for version $current_version"
          return 0
        fi
        log "Spotify updated from $patched_version to $current_version, re-patching..."
      fi
      log "Applying SpotX-Bash patch..."
      if ${pkgs.bash}/bin/bash <(${pkgs.curl}/bin/curl -sSL https://raw.githubusercontent.com/SpotX-Official/SpotX-Bash/main/spotx.sh) -P "$SPOTIFY_DIR" -f; then
        echo "$current_version" > "$PATCH_MARKER"
        log "SpotX applied successfully!"
        return 0
      else
        error "SpotX patch application failed"
        exit 1
      fi
    }

    remove_patch() {
      log "SpotX removal not supported with SpotX-Bash"
      log "Please reinstall Spotify Flatpak to remove SpotX"
      exit 1
    }

    show_status() {
      local current_version=$(get_spotify_version)
      if [ -f "$PATCH_MARKER" ]; then
        local patched_version=$(cat "$PATCH_MARKER" 2>/dev/null || echo "unknown")
        if [ "$patched_version" = "$current_version" ]; then
          echo "SpotX: applied (version: $current_version)"
          return 0
        else
          echo "SpotX: version mismatch (patched: $patched_version, current: $current_version)"
          return 1
        fi
      else
        echo "SpotX: not applied"
        return 1
      fi
    }

    case "''${1:-patch}" in
      patch) apply_patch ;;
      unpatch|remove) remove_patch ;;
      status) show_status ;;
      *) echo "Usage: $0 {patch|unpatch|status}"; exit 1 ;;
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
        # Run as root to access system Flatpak installation
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
        # Run as root to access system Flatpak installation
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

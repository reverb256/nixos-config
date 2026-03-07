# Spotify with SpotX Patch - Nixpkgs version
# Removes ads, enables DRM bypass, and unlocks premium features
# Uses pkgs.spotify (native) instead of Flatpak for better WM integration
{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.services.spotify-spotx;
  inherit (lib) mkIf mkEnableOption mkOption types;

  # Spotify package from Nixpkgs
  spotifyPackage = pkgs.spotify;
  spotifyShareDir = "${spotifyPackage}/share/spotify";

  # writable state directory for patched Spotify
  spotifyStateDir = "/var/lib/spotify-spotx";
  patchedSpotifyDir = "${spotifyStateDir}/spotify";
in
{
  options.services.spotify-spotx = {
    enable = mkEnableOption "Spotify with SpotX patch (ad-free, premium features)";

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
    # Install Spotify from Nixpkgs and wrapper scripts
    environment.systemPackages = [
      spotifyPackage
      (pkgs.writeShellScriptBin "spotify" ''
        #!${pkgs.bash}/bin/bash
        # Launch patched Spotify if exists, otherwise launch stock
        PATCHED="${patchedSpotifyDir}"
        STOCK="${spotifyShareDir}"

        # Check if patch was applied (marker file exists)
        if [ -f "$PATCHED/Apps/.spotx_patched" ]; then
          exec "$PATCHED/spotify" "$@"
        else
          exec "$STOCK/spotify" "$@"
        fi
      '')
      (pkgs.writeShellScriptBin "spotify-spotx" ''
        #!${pkgs.bash}/bin/bash
        exec /etc/spotx/patch-manager.sh "$@"
      '')
    ];

    # Create state directories
    systemd.tmpfiles.rules = [
      "d ${spotifyStateDir} 0755 root root -"
      "d ${spotifyStateDir}/backups 0755 root root -"
    ];

    # Setup script for initial installation
    environment.etc."spotx/setup-spotify.sh".source = pkgs.writeShellScript "setup-spotify.sh" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail

      RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
      log() { echo -e "''${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]''${NC} $1"; }
      error() { echo -e "''${RED}[ERROR]''${NC} $1" >&2; }

      log "=== Spotify + SpotX Initial Setup (Nixpkgs) ==="

      SOURCE_DIR="''${spotifyShareDir}"
      TARGET_DIR="''${patchedSpotifyDir}"

      # Check source Spotify exists
      if [ ! -d "$SOURCE_DIR" ]; then
        error "Spotify package not found at: $SOURCE_DIR"
        exit 1
      fi

      log "Source Spotify: $SOURCE_DIR"
      log "Target patched directory: $TARGET_DIR"

      # Create target directory and copy Spotify files
      log "Copying Spotify files to writable location..."
      mkdir -p "$TARGET_DIR"
      cp -r "$SOURCE_DIR"/* "$TARGET_DIR"/ 2>/dev/null || true

      # Ensure directory is writable
      chmod -R u+rw "$TARGET_DIR" 2>/dev/null || true

      # Apply SpotX-Bash patch
      log "Applying SpotX-Bash patch..."
      if ${pkgs.bash}/bin/bash <(${pkgs.curl}/bin/curl -sSL https://raw.githubusercontent.com/SpotX-Official/SpotX-Bash/main/spotx.sh) -P "$TARGET_DIR" -f; then
        log "✓ SpotX patch applied successfully!"

        # Create marker
        echo "patched" > "$TARGET_DIR/Apps/.spotx_patched"
      else
        error "SpotX patch application failed"
        exit 1
      fi

      log "✓ Setup complete!"
    '';

    # Patch management script
    environment.etc."spotx/patch-manager.sh".source = pkgs.writeShellScript "patch-manager.sh" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      PATH="/run/current-system/sw/bin:$PATH"

      RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
      log() { echo -e "''${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]''${NC} $1"; }
      error() { echo -e "''${RED}[ERROR]''${NC} $1" >&2; }

      SOURCE_DIR="''${spotifyShareDir}"
      TARGET_DIR="''${patchedSpotifyDir}"
      BACKUP_DIR="''${spotifyStateDir}/backups"
      PATCH_MARKER="''${TARGET_DIR}/Apps/.spotx_patched"

      apply_patch() {
        log "Starting SpotX patching..."

        if [ ! -d "$SOURCE_DIR" ]; then
          error "Spotify package not found at: $SOURCE_DIR"
          exit 1
        fi

        # Create fresh copy from Nix package
        log "Copying fresh Spotify files from Nix package..."
        mkdir -p "$TARGET_DIR"
        rm -rf "$TARGET_DIR"/*
        cp -r "$SOURCE_DIR"/* "$TARGET_DIR"/ 2>/dev/null || true

        # Make writable
        chmod -R u+rw "$TARGET_DIR" 2>/dev/null || true

        # Apply SpotX-Bash patch
        log "Applying SpotX-Bash patch..."
        if ${pkgs.bash}/bin/bash <(${pkgs.curl}/bin/curl -sSL https://raw.githubusercontent.com/SpotX-Official/SpotX-Bash/main/spotx.sh) -P "$TARGET_DIR" -f; then
          echo "patched" > "$PATCH_MARKER"
          log "SpotX applied successfully!"
          return 0
        else
          error "SpotX patch application failed"
          exit 1
        fi
      }

      show_status() {
        if [ -f "$PATCH_MARKER" ]; then
          echo "SpotX: applied at $TARGET_DIR"
          return 0
        else
          echo "SpotX: not applied"
          return 1
        fi
      }

      case "''${1:-patch}" in
        patch) apply_patch ;;
        status) show_status ;;
        *) echo "Usage: $0 {patch|status}"; exit 1 ;;
      esac
    '';

    environment.etc."spotx/patch-manager.sh".mode = "0755";

    # Main patch service - runs once at boot to ensure patch is applied
    systemd.services.spotx-patch = {
      description = "Spotify SpotX Patch Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "/etc/spotx/patch-manager.sh patch";
        StandardOutput = "journal";
        StandardError = "journal";
        User = "root";
        Group = "root";
        RemainAfterExit = true;
      };
    };

    # Auto-patch timer
    systemd.timers.spotx-patch = lib.mkIf cfg.autoPatch {
      description = "Spotify SpotX Auto-Patch Timer";
      wantedBy = [ "timers.target" ];
      partOf = [ "spotx-patch.service" ];
      timerConfig = {
        OnCalendar = cfg.patchCheckInterval;
        Unit = "spotx-patch.service";
        Persistent = true;
      };
    };
  };
}

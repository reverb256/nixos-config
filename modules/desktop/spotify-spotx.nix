# Spotify with SpotX Patch - Nixpkgs version
# Removes ads, enables DRM bypass, and unlocks premium features
# Uses pkgs.spotify (native) instead of Flatpak for better WM integration
# Version: 2.0 - Fixed Nix string escaping
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

    clearCacheOnPatch = mkOption {
      type = types.bool;
      default = true;
      description = "Clear Spotify cache after patching. Safe to enable since patch only runs when Spotify updates.";
    };
  };

  config = mkIf cfg.enable {
    # Custom Spotify package with wrapper that prefers patched version
    environment.systemPackages = [
      (pkgs.symlinkJoin {
        name = "spotify-with-spotx";
        paths = [ spotifyPackage ];
        postBuild = ''
          rm $out/bin/spotify
          cat > $out/bin/spotify <<EOF
#!${pkgs.bash}/bin/bash
if [ -f ${patchedSpotifyDir}/Apps/.spotx_patched ]; then
  exec ${patchedSpotifyDir}/spotify "\$@"
else
  exec ${spotifyShareDir}/spotify "\$@"
fi
EOF
          chmod +x $out/bin/spotify
        '';
      })
      (pkgs.writeShellScriptBin "spotify-spotx" ''
        #!${pkgs.bash}/bin/bash
        # SpotX management commands:
        #   spotify-spotx patch       - Apply SpotX patch
        #   spotify-spotx status      - Check patch status
        #   spotify-spotx clear-cache - Clear Spotify cache (fixes ads showing)
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

      SOURCE_DIR="${spotifyShareDir}"
      TARGET_DIR="${patchedSpotifyDir}"

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

        # SpotX doesn't copy .spotify-wrapped, so we need to copy it from stock
        log "Copying .spotify-wrapped binary from stock Spotify..."
        cp -f "$SOURCE_DIR"/.spotify-wrapped "$TARGET_DIR"/.spotify-wrapped
        chmod +x "$TARGET_DIR"/.spotify-wrapped

        # Fix the spotify wrapper: replace nix store path with actual target directory path
        log "Fixing spotify wrapper to use local .spotify-wrapped..."
        ${pkgs.perl}/bin/perl -pi -e "s|/nix/store/[^\"]+/share/spotify/\\.spotify-wrapped|${patchedSpotifyDir}/.spotify-wrapped|g" "$TARGET_DIR/spotify"

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

      SOURCE_DIR="${spotifyShareDir}"
      TARGET_DIR="${patchedSpotifyDir}"
      BACKUP_DIR="${spotifyStateDir}/backups"
      PATCH_MARKER="''${TARGET_DIR}/Apps/.spotx_patched"
      CLEAR_CACHE=${lib.boolToString cfg.clearCacheOnPatch}

      clear_cache() {
        log "Clearing Spotify cache for all users..."
        local cache_cleared=false

        # Clear cache for all user home directories
        for home in /home/* /root; do
          if [ -d "$home/.cache/spotify" ]; then
            local username=$(basename "$home")
            if [ "$username" != "lost+found" ]; then
              log "Clearing cache for user: $username"
              rm -rf "$home/.cache/spotify"/*
              cache_cleared=true
            fi
          fi
          if [ -d "$home/.config/spotify/Storage" ]; then
            rm -rf "$home/.config/spotify/Storage"/*
          fi
          if [ -d "$home/.config/spotify/com.spotify.client" ]; then
            rm -rf "$home/.config/spotify/com.spotify.client"/*
          fi
        done

        if [ "$cache_cleared" = true ]; then
          log "✓ Spotify cache cleared"
        else
          log "No Spotify cache found to clear"
        fi
      }

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

          # SpotX doesn't copy .spotify-wrapped, so we need to copy it from stock
          log "Copying .spotify-wrapped binary from stock Spotify..."
          cp -f "$SOURCE_DIR"/.spotify-wrapped "$TARGET_DIR"/.spotify-wrapped
          chmod +x "$TARGET_DIR"/.spotify-wrapped

          # Fix the spotify wrapper: replace nix store path with actual target directory path
          log "Fixing spotify wrapper to use local .spotify-wrapped..."
          ${pkgs.perl}/bin/perl -pi -e "s|/nix/store/[^\"]+/share/spotify/\\.spotify-wrapped|${patchedSpotifyDir}/.spotify-wrapped|g" "$TARGET_DIR/spotify"

          log "SpotX applied successfully!"

          # Clear cache so patched files are loaded
          if [ "$CLEAR_CACHE" = "true" ]; then
            clear_cache
          fi

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
        clear-cache) clear_cache ;;
        *) echo "Usage: $0 {patch|status|clear-cache}"; exit 1 ;;
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

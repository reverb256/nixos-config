# Spotify with SpotX Patch
# Removes ads, enables DRM bypass, and unlocks premium features
# Refactored to use spotify-common library
{ config, lib, pkgs, ... }:

let
  cfg = config.services.spotify-spotx;
  inherit (lib) mkIf mkEnableOption mkOption types;

  # Import common Spotify utilities
  spotifyLib = import ./lib/spotify-common.nix { inherit lib pkgs; };

  stateDir = spotifyLib.mkSpotifyStateDir "spotx";
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
    # Create state directories
    systemd.tmpfiles.rules = spotifyLib.mkSpotifyTmpfiles "spotx";

    # Setup script for initial installation
    environment.etc."spotx/setup-spotify.sh".source = pkgs.writeShellScript "setup-spotify.sh" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      ${spotifyLib.mkSpotifyLogging}

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

      ${spotifyLib.mkSpotifyPaths}

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

    # Main patch management script
    environment.etc."spotx/patch-manager.sh".source = pkgs.writeShellScript "patch-manager.sh" ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      PATH="/run/current-system/sw/bin:$PATH"

      ${spotifyLib.mkSpotifyLogging}

      ${spotifyLib.mkSpotifyPaths}

      BACKUP_DIR="${stateDir}/backups"
      PATCH_MARKER="''${SPOTIFY_DIR}/Apps/.spotx_patched"

      # Create backup directory
      if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        chmod 755 "$BACKUP_DIR"
      fi

      ${spotifyLib.mkSpotifyVersionDetector}

      ${spotifyLib.mkSpotifyPatchChecker "$PATCH_MARKER"}

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

    environment.etc."spotx/patch-manager.sh".mode = "0755";

    # Main patch service
    systemd.services.spotx-patch = spotifyLib.mkSpotifySystemdService {
      name = "spotx-patch";
      description = "Spotify SpotX Patch Service";
      execStart = "/etc/spotx/patch-manager.sh patch";
    };

    # Auto-patch timer
    systemd.timers.spotx-patch = lib.mkIf cfg.autoPatch (spotifyLib.mkSpotifySystemdTimer {
      name = "spotx-patch";
      description = "Spotify SpotX Auto-Patch Timer";
      onCalendar = cfg.patchCheckInterval;
      partOf = "spotx-patch.service";
    });

    # Run after Flatpak updates
    systemd.services.flatpak-update-after-spotx = lib.mkIf config.services.flatpak.enable {
      description = "Run SpotX patch after Flatpak updates";
      after = [ "flatpak-update.service" ];
      wants = [ "flatpak-update.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "/etc/spotx/patch-manager.sh patch";
        StandardOutput = "journal";
        StandardError = "journal";
        User = "root";
        Group = "root";
      };
    };

    # CLI wrapper
    environment.systemPackages = [
      (spotifyLib.mkSpotifyCliWrapper {
        name = "spotify-spotx";
        script = "exec /etc/spotx/patch-manager.sh \"\$@\"";
      })
    ];
  };
}

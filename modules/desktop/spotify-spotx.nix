{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.spotify-spotx;
  inherit (lib) mkIf mkEnableOption mkOption types;

  spotify-common = import ./lib/spotify-common.nix {inherit lib pkgs;};

  spotifyFlatpakId = "com.spotify.Client";
  spotifyStateDir = spotify-common.mkSpotifyStateDir "spotx";
  patchMarker = "${spotifyStateDir}/.spotx_patched";
in {
  options.services.spotify-spotx = {
    enable = mkEnableOption "Spotify Flatpak with SpotX patch (ad-free, premium features)";

    autoInstall = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically install Spotify Flatpak if not present.";
    };

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

    forceX11 = mkOption {
      type = types.bool;
      default = false;
      description = "Force X11 backend (XWayland) for Spotify. Fixes broken close button on Wayland.";
    };

    clearCacheOnPatch = mkOption {
      type = types.bool;
      default = true;
      description = "Clear Spotify cache after patching.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      (spotify-common.mkSpotifyCliWrapper {
        name = "spotify-spotx";
        script = ''
          #!${pkgs.bash}/bin/bash

          set -euo pipefail

          ${spotify-common.mkSpotifyLogging}

          ${spotify-common.mkSpotifyPaths}

          ${spotify-common.mkSpotifyVersionDetector}

          SPOTIFY_ID="${spotifyFlatpakId}"
          STATE_DIR="${spotifyStateDir}"
          PATCH_MARKER="${patchMarker}"

          check_spotify_installed() {
            ${pkgs.flatpak}/bin/flatpak list | grep -q "$SPOTIFY_ID"
          }

          install_spotify() {
            log "Installing Spotify Flatpak from Flathub..."
            if ${pkgs.flatpak}/bin/flatpak install --system flathub "$SPOTIFY_ID" -y; then
              log "✓ Spotify installed successfully"
              return 0
            else
              error "Failed to install Spotify"
              return 1
            fi
          }

          get_spotify_path() {
            ${pkgs.flatpak}/bin/flatpak info "$SPOTIFY_ID" --show-location 2>/dev/null
          }

          clear_cache() {
            log "Clearing Spotify cache for all users..."
            local cache_cleared=false

            for home in /home/* /root; do
              if [ -d "$home" ]; then
                local username=$(basename "$home")
                if [ "$username" != "lost+found" ]; then
                  if [ -d "$home/.var/app/$SPOTIFY_ID/cache" ]; then
                    log "Clearing cache for user: $username"
                    rm -rf "$home/.var/app/$SPOTIFY_ID/cache"/*
                    cache_cleared=true
                  fi
                  if [ -d "$home/.var/app/$SPOTIFY_ID/config/spotify/Storage" ]; then
                    rm -rf "$home/.var/app/$SPOTIFY_ID/config/spotify/Storage"/*
                  fi
                fi
              fi
            done

            if [ "$cache_cleared" = true ]; then
              log "✓ Spotify cache cleared"
            else
              log "No Spotify cache found to clear"
            fi
          }

          apply_patch() {
            export PATH="/run/current-system/sw/bin:${lib.makeBinPath [pkgs.bash pkgs.perl pkgs.curl]}:$PATH"

            log "Starting SpotX patching for Flatpak Spotify..."

            if ! check_spotify_installed; then
              error "Spotify Flatpak not installed. Run: spotify-spotx install"
              exit 1
            fi

            SPOTIFY_PATH=$(get_spotify_path)
            if [ -z "$SPOTIFY_PATH" ]; then
              error "Could not determine Spotify installation path"
              exit 1
            fi

            SPOTIFY_DIR="$SPOTIFY_PATH/files/extra/share/spotify"
            if [ ! -d "$SPOTIFY_DIR" ]; then
              error "Spotify directory not found at: $SPOTIFY_DIR"
              exit 1
            fi

            log "Spotify directory: $SPOTIFY_DIR"
            log "Spotify version: $(get_spotify_version)"

            log "Stopping any running Spotify instances..."
            ${pkgs.flatpak}/bin/flatpak kill "$SPOTIFY_ID" 2>/dev/null || true

            log "Applying SpotX-Bash patch..."
            if ${pkgs.bash}/bin/bash <(${pkgs.curl}/bin/curl -sSL https://raw.githubusercontent.com/SpotX-Official/SpotX-Bash/main/spotx.sh) -P "$SPOTIFY_DIR" -f; then
              log "✓ SpotX patch applied successfully!"

              ${lib.optionalString cfg.forceX11 ''
            log "Forcing X11 backend to fix Wayland CSD issues..."
            ${pkgs.perl}/bin/perl -pi -e 's|--enable-features=UseOzonePlatform --ozone-platform=wayland|--enable-features=UseOzonePlatform --ozone-platform=x11|g' "$SPOTIFY_DIR/spotify"
            log "✓ X11 backend forced"
          ''}

              mkdir -p "$STATE_DIR"
              echo "$(get_spotify_version)" > "$PATCH_MARKER"
              log "✓ Patch marker created: $(get_spotify_version)"

              ${lib.optionalString cfg.clearCacheOnPatch ''
            clear_cache
          ''}

              log "✓ SpotX patching complete!"
              return 0
            else
              error "SpotX patch application failed"
              exit 1
            fi
          }

          show_status() {
            if check_spotify_installed; then
              echo "Spotify Flatpak: installed ($(get_spotify_version))"
              SPOTIFY_PATH=$(get_spotify_path)
              echo "Installation path: $SPOTIFY_PATH"

              if [ -f "$PATCH_MARKER" ]; then
                PATCHED_VERSION=$(cat "$PATCH_MARKER")
                CURRENT_VERSION=$(get_spotify_version)
                if [ "$PATCHED_VERSION" = "$CURRENT_VERSION" ]; then
                  echo "SpotX: applied (version: $PATCHED_VERSION)"
                  return 0
                else
                  echo "SpotX: needs update (patched: $PATCHED_VERSION, current: $CURRENT_VERSION)"
                  return 1
                fi
              else
                echo "SpotX: not applied"
                return 1
              fi
            else
              echo "Spotify Flatpak: not installed"
              echo "Run: spotify-spotx install"
              return 1
            fi
          }

          case "''${1:-status}" in
            patch)
              echo "Triggering SpotX patch service..."
              if ${pkgs.systemd}/bin/systemctl start spotx-patch.service; then
                echo "✓ Patch service triggered"
                echo "Check status with: spotify-spotx status"
                echo "View logs with: journalctl -u spotx-patch.service -n 50"
              else
                error "Failed to trigger patch service"
                exit 1
              fi
              ;;
            status) show_status ;;
            clear-cache) clear_cache ;;
            install) install_spotify ;;
            launch)
              if check_spotify_installed; then
                exec ${pkgs.flatpak}/bin/flatpak run "$SPOTIFY_ID"
              else
                error "Spotify not installed. Run: spotify-spotx install"
                exit 1
              fi
              ;;
            *)
              echo "Usage: $0 {patch|status|clear-cache|install|launch}"
              echo ""
              echo "Commands:"
              echo "  patch       - Apply SpotX patch to Spotify"
              echo "  status      - Check Spotify and SpotX status"
              echo "  clear-cache - Clear Spotify cache"
              echo "  install     - Install Spotify Flatpak"
              echo "  launch      - Launch Spotify"
              exit 1
              ;;
          esac
        '';
      })
    ];

    systemd = {
      tmpfiles.rules = spotify-common.mkSpotifyTmpfiles "spotx";

      services = {
        spotx-patch = lib.mkIf cfg.autoPatch {
          description = "Spotify SpotX Patch Service (Flatpak)";
          wantedBy = ["multi-user.target"];
          after = ["network-online.target"];
          wants = ["network-online.target" "flatpak-update.service"];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "/etc/spotx/patch-service.sh";
            StandardOutput = "journal";
            StandardError = "journal";
            User = "root";
            Group = "root";
          };
        };
      };

      timers = lib.mkIf cfg.autoPatch {
        spotx-patch = {
          description = "Spotify SpotX Auto-Patch Timer (Flatpak)";
          wantedBy = ["timers.target"];
          partOf = ["spotx-patch.service"];
          timerConfig = {
            OnCalendar = cfg.patchCheckInterval;
            Unit = "spotx-patch.service";
            Persistent = true;
          };
        };
      };
    };

    system.activationScripts.spotify-spotx-setup = lib.mkIf cfg.autoInstall ''
      echo "Setting up Spotify Flatpak with SpotX..."

      if ! ${pkgs.flatpak}/bin/flatpak list | grep -q "${spotifyFlatpakId}"; then
        echo "Installing Spotify Flatpak from Flathub..."
        ${pkgs.flatpak}/bin/flatpak install --system flathub ${spotifyFlatpakId} -y || echo "Warning: Failed to install Spotify Flatpak"
      else
        echo "Spotify Flatpak already installed"
      fi
    '';

    environment.etc."spotx/patch-service.sh".source = pkgs.writeShellScript "spotx-patch-service" ''
      set -euo pipefail

      export PATH="/run/current-system/sw/bin:${lib.makeBinPath [pkgs.bash pkgs.perl pkgs.curl]}:$PATH"

      ${spotify-common.mkSpotifyLogging}

      SPOTIFY_ID="${spotifyFlatpakId}"
      PATCH_MARKER="${patchMarker}"

      ${spotify-common.mkSpotifyPaths}
      ${spotify-common.mkSpotifyVersionDetector}

      if ! ${pkgs.flatpak}/bin/flatpak list | grep -q "$SPOTIFY_ID"; then
        log "Spotify Flatpak not installed, skipping patch"
        exit 0
      fi

      CURRENT_VERSION=$(get_spotify_version)

      if [ -f "$PATCH_MARKER" ]; then
        PATCHED_VERSION=$(cat "$PATCH_MARKER")
        if [ "$PATCHED_VERSION" = "$CURRENT_VERSION" ]; then
          log "Spotify unchanged ($CURRENT_VERSION), no patch needed"
          exit 0
        fi
        log "Spotify updated ($PATCHED_VERSION -> $CURRENT_VERSION), re-patching..."
      else
        log "First-time patching Spotify $CURRENT_VERSION..."
      fi

      if [ -z "$SPOTIFY_DIR" ]; then
        log "Detecting Spotify installation path..."
        SPOTIFY_PATH=$(${pkgs.flatpak}/bin/flatpak info "$SPOTIFY_ID" --show-location 2>/dev/null)
        SPOTIFY_DIR="$SPOTIFY_PATH/files/extra/share/spotify"
      fi

      if [ ! -d "$SPOTIFY_DIR" ]; then
        log "Error: Spotify directory not found at $SPOTIFY_DIR"
        exit 1
      fi

      ${pkgs.flatpak}/bin/flatpak kill "$SPOTIFY_ID" 2>/dev/null || true

      log "Applying SpotX-Bash patch to $SPOTIFY_DIR..."
      if ${pkgs.bash}/bin/bash <(${pkgs.curl}/bin/curl -sSL https://raw.githubusercontent.com/SpotX-Official/SpotX-Bash/main/spotx.sh) -P "$SPOTIFY_DIR" -f; then
        log "SpotX patch applied successfully"

        ${lib.optionalString cfg.forceX11 ''
        log "Forcing X11 backend for Wayland CSD fix..."
        ${pkgs.perl}/bin/perl -pi -e 's|--enable-features=UseOzonePlatform --ozone-platform=wayland|--enable-features=UseOzonePlatform --ozone-platform=x11|g' "$SPOTIFY_DIR/spotify"
      ''}

        mkdir -p ${spotifyStateDir}
        echo "$CURRENT_VERSION" > "$PATCH_MARKER"
        log "Patch marker updated: $CURRENT_VERSION"

        ${lib.optionalString cfg.clearCacheOnPatch ''
        log "Clearing Spotify cache..."
        for home in /home/* /root; do
          if [ -d "$home/.var/app/$SPOTIFY_ID/cache" ]; then
            rm -rf "$home/.var/app/$SPOTIFY_ID/cache"/*
          fi
        done
        log "Cache cleared"
      ''}

        log "SpotX patching complete for Spotify $CURRENT_VERSION"
      else
        log "Error: SpotX patch failed"
        exit 1
      fi
    '';
  };
}

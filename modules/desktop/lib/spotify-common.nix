# Spotify Module Common Library
# Shared utilities for Spotify-related modules (SpotX, Spicetify)
{
  lib,
  pkgs,
}:
let
  inherit (lib) mkOption types optionalString;

  # ============================================================================
  # HELPER FUNCTIONS (defined in let for mutual reference)
  # ============================================================================

  /**
    mkSpotifyStateDir
    -----------------
    Returns a state directory path for Spotify modules.

    Example:
      mkSpotifyStateDir "spotx"  => "/var/lib/spotx"
      mkSpotifyStateDir "spicetify" => "/var/lib/spicetify"
  */
  mkSpotifyStateDir = name: "/var/lib/${name}";

  /**
    mkSpotifyTmpfiles
    -----------------
    Creates tmpfiles.rules for a Spotify module's state directory.

    Example:
      mkSpotifyTmpfiles "spotx"
      => [ "d /var/lib/spotx 0755 root root -"
         "d /var/lib/spotx/backups 0755 root root -" ]
  */
  mkSpotifyTmpfiles = name: [
    "d ${mkSpotifyStateDir name} 0755 root root -"
    "d ${mkSpotifyStateDir name}/backups 0755 root root -"
  ];

  /**
    mkSpotifyLogging
    ----------------
    Creates colored logging functions for shell scripts.

    Returns bash code that defines:
    - log() for info messages (green)
    - error() for error messages (red)
    - warn() for warnings (yellow)
  */
  mkSpotifyLogging = /* bash */ ''
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
    log() { echo -e "''${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]''${NC} $1"; }
    error() { echo -e "''${RED}[ERROR]''${NC} $1" >&2; }
    warn() { echo -e "''${YELLOW}[WARN]''${NC} $1"; }
  '';

  /**
    mkSpotifyPaths
    --------------
    Shell snippet to detect and set Spotify Flatpak paths.
  */
  mkSpotifyPaths = /* bash */ ''
    # Get Spotify Flatpak installation path
    SPOTIFY_PATH="$(${pkgs.flatpak}/bin/flatpak info com.spotify.Client --show-location 2>/dev/null)"
    SPOTIFY_DIR="''${SPOTIFY_PATH}/files/extra/share/spotify"
  '';

  /**
    mkSpotifyVersionDetector
    ------------------------
    Shell function to get the current Spotify version from Flatpak.
  */
  mkSpotifyVersionDetector = /* bash */ ''
    get_spotify_version() {
      ${pkgs.flatpak}/bin/flatpak info com.spotify.Client 2>/dev/null | grep "Version:" | awk '{print $2}' || echo "unknown"
    }
  '';

  /**
    mkSpotifyPatchChecker
    ---------------------
    Shell function to check if Spotify is patched.
    Takes a marker file path as argument.
  */
  mkSpotifyPatchChecker = markerFile: /* bash */ ''
    is_patched() {
      [ -f "${markerFile}" ] && ${pkgs.flatpak}/bin/flatpak list | grep -q "com.spotify.Client"
    }
  '';

  /**
    mkSpotifySystemdService
    -----------------------
    Creates a base systemd service configuration for Spotify modules.

    Args:
      name: Service name (e.g., "spotx-patch", "spotify-spicetify")
      description: Human-readable description
      execStart: Command to run
      extraAfter: Additional dependencies (default: [ "network-online.target" ])
  */
  mkSpotifySystemdService = {
    name,
    description,
    execStart,
    extraAfter ? [ "network-online.target" ],
  }: {
    inherit description;
    after = [ "network.target" ] ++ extraAfter;
    wants = extraAfter;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = execStart;
      StandardOutput = "journal";
      StandardError = "journal";
      User = "root";
      Group = "root";
    };
  };

  /**
    mkSpotifySystemdTimer
    ---------------------
    Creates a systemd timer configuration for Spotify auto-update.

    Args:
      name: Timer name (should match service name)
      description: Human-readable description
      onCalendar: Calendar schedule (e.g., "daily")
      partOf: Service name this timer belongs to (will be wrapped in a list)
  */
  mkSpotifySystemdTimer = {
    name,
    description,
    onCalendar,
    partOf,
  }: {
    inherit description;
    wantedBy = [ "timers.target" ];
    partOf = [ partOf ];
    timerConfig = {
      OnCalendar = onCalendar;
      Unit = partOf;
      Persistent = true;
    };
  };

  /**
    mkSpotifyCliWrapper
    -------------------
    Creates a shell script wrapper for manual control.

    Args:
      name: Command name (e.g., "spotify-spotx", "spotify-spicetify")
      script: The script content to wrap
  */
  mkSpotifyCliWrapper = {
    name,
    script,
  }:
    pkgs.writeShellScriptBin name script;

  # ============================================================================
  # MODULE OPTIONS
  # ============================================================================

  /**
    spotifyAutoUpdateOptions
    ------------------------
    Standard options for Spotify auto-update functionality.
    Include this in your module's options section.
  */
  spotifyAutoUpdateOptions = {
    autoApply = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically apply when Spotify updates.";
    };

    checkInterval = mkOption {
      type = types.str;
      default = "daily";
      description = "How often to check and re-apply (systemd timer format).";
    };
  };

in {
  inherit
    mkSpotifyLogging
    mkSpotifyPaths
    mkSpotifyVersionDetector
    mkSpotifyPatchChecker
    mkSpotifyStateDir
    mkSpotifyTmpfiles
    mkSpotifySystemdService
    mkSpotifySystemdTimer
    mkSpotifyCliWrapper
    spotifyAutoUpdateOptions
    ;
}

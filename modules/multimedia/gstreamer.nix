# GStreamer Multimedia Support
# Provides GStreamer plugins and codec support for Qt/KDE multimedia applications
# Fixes issues with Audiotube and other Qt Multimedia apps on NixOS
{ config, lib, pkgs, ... }:

with lib; let
  cfg = config.services.multimedia.gstreamer;
in {
  options.services.multimedia.gstreamer = {
    enable = mkEnableOption "GStreamer multimedia support for Qt/KDE applications";

    codecs = {
      enableBase = mkOption {
        type = types.bool;
        default = true;
        description = "Enable base GStreamer plugins (videoconvert, audioconvert, etc.)";
      };

      enableGood = mkOption {
        type = types.bool;
        default = true;
        description = "Enable good GStreamer plugins (common codecs: MP3, VP8, etc.)";
      };

      enableBad = mkOption {
        type = types.bool;
        default = true;
        description = "Enable bad GStreamer plugins (less common codecs: H.264, AAC, etc.)";
      };

      enableUgly = mkOption {
        type = types.bool;
        default = true;
        description = "Enable ugly GStreamer plugins (patent-encumbered codecs)";
      };

      enableLibav = mkOption {
        type = types.bool;
        default = true;
        description = "Enable libav wrapper plugins (FFmpeg codecs)";
      };
    };
  };

  config = mkIf cfg.enable {
    # ============================================================================
    # GSTREAMER PACKAGES
    # ============================================================================
    # Core GStreamer packages required by Qt Multimedia backend
    environment.systemPackages = with pkgs;
      [
        # GStreamer core framework
        gst_all_1.gstreamer

        # Base plugins - REQUIRED for videoconvert/audioconvert
        # These provide fundamental elements that Qt Multimedia depends on
      ] ++ optionals cfg.codecs.enableBase [
        gst_all_1.gst-plugins-base

        # Development headers (for building apps that use GStreamer)
        gst_all_1.gst-plugins-base.dev
      ]
      ++ optionals cfg.codecs.enableGood [
        # Good plugins - high quality plugins under GPL
        # Includes: MP3, VP8, OGG, FLAC, WAV, Opus, etc.
        gst_all_1.gst-plugins-good
      ]
      ++ optionals cfg.codecs.enableBad [
        # Bad plugins - plugins under LGPL that need more review
        # Includes: H.264, AAC, ALSA, JACK, PipeWire, etc.
        gst_all_1.gst-plugins-bad
      ]
      ++ optionals cfg.codecs.enableUgly [
        # Ugly plugins - good quality plugins with distribution issues
        # Includes: AAC, MP3, Xvid, etc. (patent/licensing issues)
        gst_all_1.gst-plugins-ugly
      ]
      ++ optionals cfg.codecs.enableLibav [
        # libav wrapper - provides FFmpeg codecs via GStreamer
        # Includes: H.264, H.265, VP9, AV1, etc.
        gst_all_1.gst-libav
      ];

    # ============================================================================
    # ENVIRONMENT CONFIGURATION
    # ============================================================================
    # Ensure Qt Multimedia uses GStreamer backend
    environment.sessionVariables = {
      QT_MEDIA_BACKEND = "gstreamer";

      # Help Qt find GStreamer plugins at runtime
      # Note: Use /run/current-system/sw path for runtime discovery
      GST_PLUGIN_PATH = "/run/current-system/sw/lib/gstreamer-1.0";
      GST_PLUGIN_SYSTEM_PATH = "/run/current-system/sw/lib/gstreamer-1.0";

      # Enable GStreamer debug logging (useful for troubleshooting)
      # Uncomment to debug:
      # GST_DEBUG = "3";
    };

    # ============================================================================
    # PIPEWIRE INTEGRATION
    # ============================================================================
    # Ensure PipeWire is properly configured for GStreamer
    services.pipewire = {
      # Enable GStreamer plugin for PipeWire integration
      extraConfig = {
        pipewire."99-gstreamer-support"."context.modules" = [
          {
            name = "libpipewire-module-protocol-pulse";
            args = {};
          }
        ];
      };
    };

    # ============================================================================
    # DOCUMENTATION
    # ============================================================================
    # Add documentation for troubleshooting
    documentation.doc.enable = true;

    # ============================================================================
    # VERIFICATION COMMANDS
    # ============================================================================
    # After rebuild, test GStreamer with these commands:
    #
    # 1. Verify GStreamer installation:
    #    gst-inspect-1.0 --version
    #
    # 2. Check for required elements:
    #    gst-inspect-1.0 videoconvert
    #    gst-inspect-1.0 audioconvert
    #
    # 3. Test audio playback:
    #    gst-launch-1.0 audiotestsrc ! audioconvert ! autoaudiosink
    #
    # 4. Test video playback:
    #    gst-launch-1.0 videotestsrc ! videoconvert ! autovideosink
    #
    # 5. List all available plugins:
    #    gst-inspect-1.0 | grep -E "(videoconvert|audioconvert)"
    #
    # 6. Run Audiotube and check for GStreamer errors:
    #    audiotube 2>&1 | grep -i gstreamer
    #
    # ============================================================================
  };
}

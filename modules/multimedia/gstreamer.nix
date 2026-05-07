{
  config,
  lib,
  pkgs,
  ...
}:
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
    environment.systemPackages = with pkgs;
      [
        gst_all_1.gstreamer
      ]
      ++ optionals cfg.codecs.enableBase [
        gst_all_1.gst-plugins-base

        gst_all_1.gst-plugins-base.dev
      ]
      ++ optionals cfg.codecs.enableGood [
        gst_all_1.gst-plugins-good
      ]
      ++ optionals cfg.codecs.enableBad [
        gst_all_1.gst-plugins-bad
      ]
      ++ optionals cfg.codecs.enableUgly [
        gst_all_1.gst-plugins-ugly
      ]
      ++ optionals cfg.codecs.enableLibav [
        gst_all_1.gst-libav
      ];

    environment.variables = {
      QT_MEDIA_BACKEND = lib.mkForce "gstreamer";

      GST_PLUGIN_PATH = "/run/current-system/sw/lib/gstreamer-1.0";
      GST_PLUGIN_SYSTEM_PATH = "/run/current-system/sw/lib/gstreamer-1.0";
    };

    services.pipewire = {
      extraConfig = {
        pipewire."99-gstreamer-support"."context.modules" = [
          {
            name = "libpipewire-module-protocol-pulse";
            args = {};
          }
        ];
      };
    };

    documentation.doc.enable = true;
  };
}

{
  config,
  lib,
  pkgs,
  ...
}: {
  options.environment.common = {
    wayland = {
      enable = lib.mkEnableOption "Common Wayland environment variables";

      qtPlatform = lib.mkOption {
        type = lib.types.str;
        default = "wayland;xcb";
        example = "wayland";
        description = "QT_QPA_PLATFORM value for Qt applications";
      };

      ozonePlatform = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable NIXOS_OZONE_WL for Ozone Wayland support";
      };

      softwareCursors = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable WLR_NO_HARDWARE_CURSORS for software cursor rendering";
      };
    };

    cuda = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable CUDA environment variables (CUDA_PATH, CUDA_HOME)";
      };
    };

    rocm = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable ROCm environment variables (ROCM_PATH)";
      };
    };

    wine = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable WINE_FULLSCREEN_FAKE_CAPTURE";
      };
    };

    development = {
      editor = lib.mkOption {
        type = lib.types.str;
        default = "nvim";
        example = "vim";
        description = "Default editor (EDITOR and VISUAL)";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf config.environment.common.wayland.enable {
      environment.sessionVariables = {
        QT_QPA_PLATFORM = config.environment.common.wayland.qtPlatform;

        NIXOS_OZONE_WL = lib.optionalString config.environment.common.wayland.ozonePlatform "1";

        WLR_NO_HARDWARE_CURSORS = lib.optionalString config.environment.common.wayland.softwareCursors "1";

        QT_AUTO_SCREEN_SCALE_FACTOR = "1";

        QT_QPA_GL_VERSION = "2";
      };
    })

    (lib.mkIf config.environment.common.cuda.enable {
      environment.sessionVariables = {
        CUDA_PATH = "/run/opengl-driver";
        CUDA_HOME = "/run/opengl-driver";
      };
    })

    (lib.mkIf config.environment.common.rocm.enable {
      environment.sessionVariables = {
        ROCM_PATH = "${pkgs.rocmPackages.clr}";
      };
    })

    (lib.mkIf config.environment.common.wine.enable {
      environment.sessionVariables = {
        WINE_FULLSCREEN_FAKE_CAPTURE = "1";
      };
    })

    (lib.mkMerge [
      (lib.mkIf (config.environment.common.development.editor != null) {
        environment.sessionVariables = {
          EDITOR = config.environment.common.development.editor;
          VISUAL = config.environment.common.development.editor;
        };
      })
    ])
  ];
}

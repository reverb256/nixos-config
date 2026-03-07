# LobeHub - AI Agent Workspace
# Self-hosted AI platform for agent collaboration and multi-model management
# Installed via AppImage wrapper
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkOption types;

  cfg = config.desktop.lobehub;
in {
  options.desktop.lobehub = {
    enable = mkEnableOption "LobeHub AI workspace desktop application";

    package = mkOption {
      type = types.package;
      default = pkgs.lobehub;
      description = "LobeHub package to use";
    };
  };

  config = mkIf cfg.enable {
    # Define the LobeHub package using appimageTools
    environment.systemPackages = [
      (pkgs.appimageTools.wrapType2 rec {
        name = "lobehub";
        src = pkgs.fetchurl {
          url = "https://github.com/lobehub/lobe-desktop/releases/download/v2.1.38/LobeHub-2.1.38.AppImage";
          sha256 = "1da9pfwbz6r6rkigh5ljn0phq7iw4p9awr5258ww2qrdng2dy680";
        };
      })
    ];

    # Create desktop entry for application menu
    xdg.mimeApps = {
      defaultApplications = {
        "x-scheme-handler/lobehub" = ["lobehub.desktop"];
      };
    };

    # Create .desktop file
    environment.etc."xdg/autostart/lobehub.desktop".text = ''
      [Desktop Entry]
      Name=LobeHub
      GenericName=AI Agent Workspace
      Comment=Collaborate with AI agent teammates that grow with you
      Exec=lobehub-desktop %U
      Icon=lobehub
      Terminal=false
      Type=Application
      Categories=Utility;Development;Office;
      Keywords=AI;Chat;Agents;LLM;
      MimeType=x-scheme-handler/lobehub;
    '';
  };
}

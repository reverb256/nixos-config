{
  config,
  inputs,
  lib,
  pkgs,
  ...
}: let
  hostName = config.networking.hostName;
in {
  home-manager = {
    useGlobalPkgs = false;

    useUserPackages = true;

    # Use a unique backup extension that won't collide with previous backups
    # This prevents the "existing backup would be clobbered" error
    backupFileExtension = "hm-backup";

    extraSpecialArgs = {
      inherit inputs;
      inherit hostName;
    };

    users.j_kro = {...}: {
      imports = [
        inputs.niri.homeModules.config
        inputs.zen-browser.homeModules.twilight
        inputs.nixcord.homeModules.nixcord
        ../../modules/home-manager/fish.nix
        ../../modules/home-manager/starship.nix
        # ../../modules/home-manager/wayland-tools.nix
        ../../modules/home-manager/zen-browser.nix
        ../../modules/home-manager/nixcord-config.nix
        ../../modules/home-manager/caprine.nix
        ../../modules/home-manager/niri-config.nix
        # ../../modules/home-manager/obsidian.nix  # Temporarily disabled - stylix integration issue
        ../../modules/home-manager/opencode.nix
        ../../modules/home-manager/firefox-pwa-apps.nix
        ../../modules/home-manager/alacritty.nix
        ../../modules/home-manager/icon-theme.nix
        ../../modules/home-manager/dolphin.nix
        ../../modules/home-manager/desktop-utilities.nix
        ../../modules/home-manager/copyq.nix
        ../../modules/home-manager/git.nix
        ../../modules/home-manager/tmux.nix
        ../../modules/home-manager/lazygit.nix
        ../../modules/home-manager/mime-apps.nix
        ../../modules/home-manager/tui-apps.nix
        ../../modules/home-manager/editorconfig.nix
        ../../modules/home-manager/btop.nix
      ];

      nixcord-config.enable = lib.mkForce (hostName == "zephyr");
      caprine.enable = lib.mkForce (hostName == "zephyr");

      # Stylix - inherit from system config for home-manager
      stylix = {
        inherit (config.stylix) base16Scheme;
        inherit (config.stylix) image;
      };

      # CopyQ clipboard manager (replaces cliphist)
      programs.copyq = {
        enable = true;
      };

      home.sessionVariables.BAT_THEME = "base16";

      home.stateVersion = "26.05";
      home.enableNixpkgsReleaseCheck = false;

      xdg.configFile = {
        "mimeapps.list".force = true;
      };

      home.sessionVariables = {
        HF_TOKEN = "/run/agenix/huggingface-token";
      };
    };
  };
}

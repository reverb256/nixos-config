{
  config,
  inputs,
  lib,
  ...
}:
let
  hostName = config.networking.hostName;
in
{
  home-manager = {
    useGlobalPkgs = true;

    useUserPackages = true;

    # Use a unique backup extension that won't collide with previous backups
    # This prevents the "existing backup would be clobbered" error
    backupFileExtension = "hm-backup";

    users.j_kro =
      { pkgs, ... }:
      {
        imports = [
          inputs.zen-browser.homeModules.twilight
          inputs.nixcord.homeModules.nixcord
          ../../modules/home-manager/fish.nix
          ../../modules/home-manager/starship.nix
          ../../modules/home-manager/wayland-tools.nix
          ../../modules/home-manager/zen-browser.nix
          ../../modules/home-manager/nixcord-config.nix
          ../../modules/home-manager/caprine.nix
          ../../modules/home-manager/niri-config.nix
          ../../modules/home-manager/obsidian.nix
          ../../modules/home-manager/opencode.nix
          ../../modules/home-manager/firefox-pwa-apps.nix
          ../../modules/home-manager/ghostty.nix
          ../../modules/home-manager/icon-theme.nix
          ../../modules/home-manager/dolphin.nix
          ../../modules/home-manager/desktop-utilities.nix
        ];

        disabledModules = [ "stylix/hm/opencode.nix" ];
        stylix.targets.opencode.enable = false;

        stylix.targets = {
          zen-browser.profileNames = ["default"];
          qt.platform = "qtct";
        };

        nixcord-config.enable = lib.mkForce (hostName == "zephyr");
        caprine.enable = lib.mkForce (hostName == "zephyr");


        home.stateVersion = "26.05";

        xdg.configFile = {
          "mimeapps.list".force = true;
        };

        systemd.user.sessionVariables = {
          HF_TOKEN = "/run/agenix/huggingface-token";
        };
      };
  };
}

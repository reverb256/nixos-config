# Home Manager User Configuration
# Shared Home Manager configuration for j_kro across all cluster nodes
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
    # Use system package set (efficiency: single nixpkgs evaluation)
    # Overlays defined at system level affect both system and user packages
    useGlobalPkgs = true;

    # Install packages to user profile (~/.local/share/home-manager)
    # rather than /nix/var/nix/profiles/per-user/root
    useUserPackages = true;

    # Automatic backups for idempotency - handles conflicting files gracefully
    # Files are backed up with .backup extension before being replaced by symlinks
    backupFileExtension = "backup";

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
        ];

        # Enable vesktop and caprine only on Zephyr
        nixcord-config.enable = lib.mkForce (hostName == "zephyr");
        caprine.enable = lib.mkForce (hostName == "zephyr");

        # NOTE: vesktop is provided by nixcord - no need to install explicitly
        # Having both nixcord AND explicit vesktop causes build conflict:
        # "two given paths contain a conflicting subpath: .../vesktop"

        home.stateVersion = "26.05";

        # Force-overwrite all XDG config files to prevent backup conflicts
        # This makes Home Manager idempotent across rebuilds
        xdg.configFile = {
          "mimeapps.list".force = true;
        };

        # systemd user environment for secrets (available in all shells)
        systemd.user.sessionVariables = {
          HF_TOKEN = "/run/agenix/huggingface-token";
        };
      };
  };
}

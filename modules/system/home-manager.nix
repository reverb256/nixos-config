# Home Manager User Configuration
# Shared Home Manager configuration for j_kro across all cluster nodes
{
  inputs,
  ...
}: {
  home-manager = {
    # Use system package set (efficiency: single nixpkgs evaluation)
    # Overlays defined at system level affect both system and user packages
    useGlobalPkgs = true;

    # Install packages to user profile (~/.local/share/home-manager)
    # rather than /nix/var/nix/profiles/per-user/root
    useUserPackages = true;

    backupFileExtension = "bak";

    # Pass inputs to user configs so flake inputs are accessible
    extraSpecialArgs = {inherit inputs;};

    users.j_kro = {pkgs, inputs, ...}: {
      imports = [
        inputs.zen-browser.homeModules.twilight
        inputs.nixcord.homeModules.nixcord
        ../../modules/home-manager/fish.nix
        ../../modules/home-manager/starship.nix
        ../../modules/home-manager/wayland-tools.nix
        ../../modules/home-manager/nixcord-config.nix
        ../../modules/home-manager/zen-browser.nix
      ];

      home.stateVersion = "26.05";

      # systemd user environment for secrets (available in all shells)
      systemd.user.sessionVariables = {
        HF_TOKEN = "/run/agenix/huggingface-token";
      };
    };
  };
}

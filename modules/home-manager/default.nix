# Home Manager Configuration - Main Entry Point
# Centralized user configuration for j_kro across all cluster nodes
{inputs, ...}: {
  home-manager = {
    backupFileExtension = "bak";

    # Pass inputs to user configs so flake inputs are accessible
    extraSpecialArgs = {inherit inputs;};

    users.j_kro = {inputs, ...}: {
      imports = [
        inputs.zen-browser.homeModules.twilight
        inputs.nixcord.homeModules.nixcord
        ./fish.nix
        {config, ...}: {
          imports = [./starship.nix];
          # Host-specific prompt colors passed to Starship
          programs.starship.settings = {
            # Hostname color - different for each cluster node
            hostname.style =
              {
                zephyr = "bold green";
                nexus = "bold blue";
                forge = "bold red";
                sentry = "bold yellow";
              }.${config.networking.hostName} or "bold white";
            # Character prompt color matches hostname
            character.success_symbol =
              {
                zephyr = "[❯](bold green)";
                nexus = "[❯](bold blue)";
                forge = "[❯](bold red)";
                sentry = "[❯](bold yellow)";
              }.${config.networking.hostName} or "[❯](bold cyan)";
          };
        }
        ./wayland-tools.nix
        ./zen-browser.nix
        ./nixcord-config.nix
      ];

      home.stateVersion = "26.05";

      # systemd user environment for secrets (available in all shells)
      systemd.user.sessionVariables = {
        HF_TOKEN = "/run/agenix/huggingface-token";
      };
    };
  };
}

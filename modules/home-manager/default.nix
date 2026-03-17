# Home Manager Configuration - Main Entry Point
# Centralized user configuration for j_kro across all cluster nodes
{inputs, ...}: {
  home-manager = {
    # No backups - configs are declarative and version-controlled
    backupFileExtension = null;

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
        {
          # Force manage mimeapps.list to prevent clobber errors
          # This makes the configuration idempotent
          xdg.mimeApps = {
            enable = true;
            defaultApplications = {
              "text/html" = ["zen-browser.desktop"];
              "x-scheme-handler/http" = ["zen-browser.desktop"];
              "x-scheme-handler/https" = ["zen-browser.desktop"];
              "x-scheme-handler/about" = ["zen-browser.desktop"];
              "x-scheme-handler/unknown" = ["zen-browser.desktop"];
            };
          };
        }
      ];

      home.stateVersion = "26.05";

      # systemd user environment for secrets (available in all shells)
      systemd.user.sessionVariables = {
        HF_TOKEN = "/run/agenix/huggingface-token";
      };
    };
  };
}

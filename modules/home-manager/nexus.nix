# Nexus Home-Manager Configuration
# Primary server, AI, monitoring

{ config, lib, pkgs, ... }:
{
  home-manager.users.j_kro = { pkgs, ... }: {
    # AI tools configuration
    home.packages = with pkgs; [
      # Terminal
      alacritty
      kitty

      # Monitoring
      btop
      glances
      htop

      # Development
      neovim
      tmux
      lazygit

      # AI tools
      ollama
      vllm-env
      cudaPackages.cudnn
    ];

    # AI development environment
    home.sessionVariables = {
      CUDA_HOME = "/run/opengl-driver";
      LD_LIBRARY_PATH = "${pkgs.cudaPackages.cudnn}/lib";
    };

    # Container tools
    programs.podman.enable = true;

    # Development config
    home.file.".config/nvim/init.lua".source = ../../dev/nvim.lua;
    home.file.".config/tmux/tmux.conf".source = ../../dev/tmux.conf;

    # Galaxy monitoring dashboard
    xdg.configFile."galaxy/config.yml".source = ../../monitoring/galaxy.yml;

    # NOT managed: ~/models (94G), ~/projects (1.2G), .cache (28G)
    # These are user data, not configuration
  };
}
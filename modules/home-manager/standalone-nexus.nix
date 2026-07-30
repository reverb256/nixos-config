{ pkgs, ... }:
{
  home.packages = with pkgs; [
    alacritty
    kitty
    btop
    glances
    htop
    neovim
    tmux
    lazygit
    ollama
    vllm-env
    cudaPackages.cudnn
  ];

  home.sessionVariables = {
    CUDA_HOME = "/run/opengl-driver";
    LD_LIBRARY_PATH = "${pkgs.cudaPackages.cudnn}/lib";
  };

  programs.podman.enable = true;

  home.file.".config/nvim/init.lua".source = ../../dev/nvim.lua;
  home.file.".config/tmux/tmux.conf".source = ../../dev/tmux.conf;
  xdg.configFile."galaxy/config.yml".source = ../../monitoring/galaxy.yml;
}

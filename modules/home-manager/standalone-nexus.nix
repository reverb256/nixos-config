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

  home.file.".config/nvim/init.lua".source = ../../dev/nvim.lua;
  # tmux.conf owned by programs.tmux (shared leaf set) to avoid managed-file conflict
  xdg.configFile."galaxy/config.yml".source = ../../monitoring/galaxy.yml;
}

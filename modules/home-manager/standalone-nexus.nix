{ pkgs, lib, ... }:
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

  # Optional personalization seeds — only applied if the source file exists in
  # the flake tree. Keeps the standalone HM layer buildable even when these
  # per-host seed files are absent (pre-existing gap: monitoring/dev dirs not
  # committed). When present, they seed the user's first config; HM then owns
  # the managed path thereafter.
  home.file.".config/nvim/init.lua" = lib.mkIf (builtins.pathExists ../../dev/nvim.lua) {
    source = ../../dev/nvim.lua;
  };
  xdg.configFile."galaxy/config.yml" = lib.mkIf (builtins.pathExists ../../monitoring/galaxy.yml) {
    source = ../../monitoring/galaxy.yml;
  };
}

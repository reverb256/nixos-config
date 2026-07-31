{ pkgs, lib, ... }:
let
  # Resilient package inclusion: include `name` from pkgs only if it evaluates
  # without error. Protects the standalone HM layer from packages that are
  # currently broken/refuse-evaluation in the active nixpkgs (e.g. vllm-env).
  # When the package becomes evaluable, it is picked up automatically.
  tryPkg = name:
    let r = builtins.tryEval (builtins.hasAttr name pkgs && pkgs.${name});
    in lib.optional (r.success && r.value != null) r.value;
  # cudnn is a heavy CUDA dep that can fail remote-builder store checks; include
  # only when it evaluates cleanly.
  cudnn = tryPkg "cudaPackages.cudnn";
in {
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
  ] ++ tryPkg "vllm-env"
    ++ cudnn;

  home.sessionVariables = lib.mkIf (cudnn != []) {
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

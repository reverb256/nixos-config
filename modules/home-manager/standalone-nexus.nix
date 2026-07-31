{ pkgs, lib, ... }:
let
  # Resilient package inclusion: return `[pkg]` only if `name` exists in pkgs
  # AND evaluates to a derivation WITHOUT throwing. `tryEval` guards against
  # packages that refuse evaluation in the active nixpkgs (e.g. vllm-env). When a
  # package becomes evaluable, it is picked up automatically on the next build.
  safePkg = name:
    if builtins.hasAttr name pkgs
    then
      let r = builtins.tryEval pkgs.${name};
      in if r.success
           && builtins.isAttrs r.value
           && r.value ? type
           && r.value.type == "derivation"
         then [ r.value ]
         else []
    else [];
  # cudnn is a nested attr (cudaPackages.cudnn); guard via tryEval (nested path
  # access can throw even when the parent exists).
  cudnn =
    let r = builtins.tryEval pkgs.cudaPackages.cudnn;
    in if r.success
         && builtins.isAttrs r.value
         && r.value ? type
         && r.value.type == "derivation"
       then [ r.value ]
       else [];
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
  ] ++ safePkg "vllm-env"
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

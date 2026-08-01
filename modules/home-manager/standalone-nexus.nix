{ pkgs, lib, ... }:
let
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
  # NOTE: GPU/ML tooling (vllm-env and similar) is intentionally NOT managed by
  # Home Manager here. vllm-env is unavailable in the current nixpkgs and CUDA/ML
  # stacks belong in Layer 3 (nix profile), where a working flake/overlay can be
  # pinned independently of the HM cadence. HM (Layer 2) owns config + stable
  # user packages; heavy ML binaries deploy via `nix profile install` (Layer 3).
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
  ] ++ cudnn;

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

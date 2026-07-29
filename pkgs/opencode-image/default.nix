# Opencode container image for K8s deployment.
# Extracted from inline `dockerTools.buildImage` block in flake.nix on
# 2026-07-29 (audit change 3). Layers pkgs.opencode + essential shell
# tools into a thin container with OPENCODE_CONFIG_DIR=/home/j_kro/.opencode.
#
# Use: `pkgs.callPackage ./pkgs/opencode-image { }` from flake.nix.
{
  pkgs,
}:
pkgs.dockerTools.buildImage {
  name = "opencode";
  tag = "nixos";
  copyToRoot = pkgs.buildEnv {
    name = "opencode-root";
    paths = [
      pkgs.opencode
      pkgs.bash
      pkgs.coreutils
      pkgs.fish
      pkgs.git
    ];
    pathsToLink = [
      "/bin"
      "/etc"
      "/lib"
      "/home/j_kro/.nix-profile"
    ];
  };
  config = {
    Cmd = [
      "${pkgs.bash}/bin/bash"
      "-c"
      "mkdir -p /home/j_kro/.opencode && tail -f /dev/null"
    ];
    WorkingDir = "/home/j_kro";
    Env = [
      "HOME=/home/j_kro"
      "USER=j_kro"
      "PATH=/home/j_kro/.nix-profile/bin:/bin"
      "OPENCODE_CONFIG_DIR=/home/j_kro/.opencode"
      "SHELL=/bin/fish"
    ];
    Labels = {
      "org.opencontainers.image.title" = "OpenCode";
      "org.opencontainers.image.description" = "Opencode AI coding assistant";
    };
  };
}

# Claude Code container image for K8s deployment.
# Extracted from inline `dockerTools.buildImage` block in flake.nix on
# 2026-07-29 (audit change 3). Replicates the prior behavior verbatim:
# layers pkgs.claude-code + essential shell tools (bash/coreutils/git/
# gnugrep/gnused) into a thin container, drops the user at /home/j_kro
# with a tail-on-dev/null Cmd so a deployment waits for the orchestration
# hook to inject the entrypoint script.
#
# Use: `pkgs.callPackage ./pkgs/claude-code-image { }` from flake.nix.
{
  pkgs,
}:
pkgs.dockerTools.buildImage {
  name = "claude-code";
  tag = "nixos";
  copyToRoot = pkgs.buildEnv {
    name = "claude-code-root";
    paths = [
      pkgs.claude-code
      pkgs.bash
      pkgs.coreutils
      pkgs.git
      pkgs.gnugrep
      pkgs.gnused
    ];
    pathsToLink = [
      "/bin"
      "/etc"
      "/lib"
    ];
  };
  config = {
    Cmd = [
      "${pkgs.bash}/bin/bash"
      "-c"
      "mkdir -p /home/j_kro/.claude && tail -f /dev/null"
    ];
    WorkingDir = "/home/j_kro";
    Env = [
      "HOME=/home/j_kro"
      "USER=j_kro"
      "PATH=/bin"
      "CLAUDE_CONFIG_DIR=/home/j_kro/.claude"
      "SHELL=/bin/bash"
    ];
    ExposedPorts = {
      "8080/tcp" = { };
    };
    Labels = {
      "org.opencontainers.image.title" = "Claude Code";
      "org.opencontainers.image.description" = "Claude Code AI coding assistant";
    };
  };
}

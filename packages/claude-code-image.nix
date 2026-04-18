{ dockerTools, buildEnv, bash, coreutils, fish, git, gnugrep, gnused, claude-code }:
dockerTools.buildImage {
  name = "claude-code";
  tag = "nixos";
  copyToRoot = buildEnv {
    name = "claude-code-root";
    paths = [
      claude-code
      bash
      coreutils
      fish
      git
      gnugrep
      gnused
    ];
    pathsToLink = [
      "/bin"
      "/etc"
      "/lib"
    ];
  };
  config = {
    Cmd = [
      "${bash}/bin/bash"
      "-c"
      "mkdir -p /home/j_kro/.claude && tail -f /dev/null"
    ];
    WorkingDir = "/home/j_kro";
    Env = [
      "HOME=/home/j_kro"
      "USER=j_kro"
      "PATH=/bin"
      "CLAUDE_CONFIG_DIR=/home/j_kro/.claude"
      "SHELL=/bin/fish"
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

{ inputs, _final, prev }:
{
  claude-code-image = prev.dockerTools.buildImage {
    name = "claude-code";
    tag = "nixos";
    copyToRoot = prev.buildEnv {
      name = "claude-code-root";
      paths = with prev; [
        bash coreutils fish git gnugrep gnused claude-code
      ];
      pathsToLink = [ "/bin" "/etc" "/lib" ];
    };
    config = {
      Cmd = [
        "${prev.bash}/bin/bash"
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
      ExposedPorts = { "8080/tcp" = {}; };
      Labels = {
        "org.opencontainers.image.title" = "Claude Code";
        "org.opencontainers.image.description" = "Claude Code AI coding assistant";
      };
    };
  };
  ai-inference-gateway-image = prev.callPackage ../pkgs/ai-inference-gateway-image {};
  opencode-image = prev.dockerTools.buildImage {
    name = "opencode";
    tag = "nixos";
    copyToRoot = prev.buildEnv {
      name = "opencode-root";
      paths = with prev; [
        bash coreutils fish git opencode
      ];
      pathsToLink = [ "/bin" "/etc" "/lib" "/home/j_kro/.nix-profile" ];
    };
    config = {
      Cmd = [
        "${prev.bash}/bin/bash"
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
        "org.opencontainers.image.description" = "OpenCode AI coding assistant";
      };
    };
  };
}

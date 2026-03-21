# NixOS-based Claude Code container image
# Build: nix-build /etc/nixos/kubernetes-manifests/ai-coding-tools/claude-code-container.nix
# Load: docker load < result
# Tag: docker tag claude-code:nixos localhost/claude-code:nixos
{
  pkgs,
  lib,
  ...
}: let
  # Claude Code wrapper script that sets up the environment
  claudeWrapper = pkgs.writeShellScriptBin "claude-code-entry" ''
    #!${pkgs.bash}/bin/bash
    set -e

    export HOME=/home/j_kro
    export USER=j_kro
    export CLAUDE_CONFIG_DIR=/home/j_kro/.claude
    export CLAUDE_HISTORY_FILE=/home/j_kro/.claude/history.jsonl

    # Ensure config directory exists
    mkdir -p /home/j_kro/.claude/{backups,debug,file-history,paste-cache,plans,plugins,projects}

    echo "Claude Code container starting..."
    echo "Config: $CLAUDE_CONFIG_DIR"
    echo "Version: ${pkgs.claude-code.version}"

    # Keep container running for interactive exec sessions
    # Users will: kubectl exec -it <pod> -- claude
    exec tail -f /dev/null
  '';

in
  pkgs.dockerTools.buildImage {
    name = "claude-code";
    tag = "nixos";

    # Include Claude Code and dependencies
    contents = [
      pkgs.bash
      pkgs.coreutils
      pkgs.claude-code
      pkgs.fish
      pkgs.git
      pkgs.gnugrep
      pkgs.gnused
      claudeWrapper
    ];

    # Set up the container environment
    config = {
      Cmd = ["${claudeWrapper}/bin/claude-code-entry"];
      WorkingDir = "/home/j_kro";
      Env = [
        "HOME=/home/j_kro"
        "USER=j_kro"
        "PATH=/run/current-system/sw/bin:/usr/bin:/bin"
        "CLAUDE_CONFIG_DIR=/home/j_kro/.claude"
        "SHELL=/run/current-system/sw/bin/fish"
      ];
      ExposedPorts = {
        "8080/tcp" = {};
      };
      Labels = {
        "org.opencontainers.image.title" = "Claude Code";
        "org.opencontainers.image.description" = "Claude Code AI coding assistant";
        "org.opencontainers.image.version" = pkgs.claude-code.version;
      };
    };
  }

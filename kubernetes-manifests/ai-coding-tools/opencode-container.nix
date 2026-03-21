# NixOS-based OpenCode container image
# Build: nix-build /etc/nixos/kubernetes-manifests/ai-coding-tools/opencode-container.nix
# Load: docker load < result
# Tag: docker tag opencode:nixos localhost/opencode:nixos
{
  pkgs,
  lib,
  ...
}: let
  # OpenCode wrapper script that sets up the environment
  opencodeWrapper = pkgs.writeShellScriptBin "opencode-entry" ''
    #!${pkgs.bash}/bin/bash
    set -e

    export HOME=/home/j_kro
    export USER=j_kro
    export OPENCODE_CONFIG_DIR=/home/j_kro/.opencode

    # Ensure config directory exists
    mkdir -p /home/j_kro/.opencode

    echo "OpenCode container starting..."
    echo "Config: $OPENCODE_CONFIG_DIR"

    # Keep container running for interactive exec sessions
    # Users will: kubectl exec -it <pod> -- opencode
    exec tail -f /dev/null
  '';

in
  pkgs.dockerTools.buildImage {
    name = "opencode";
    tag = "nixos";

    # Include OpenCode and dependencies
    contents = [
      pkgs.bash
      pkgs.coreutils
      pkgs.opencode
      pkgs.fish
      pkgs.git
      pkgs.gnugrep
      pkgs.gnused
      opencodeWrapper
    ];

    # Set up the container environment
    config = {
      Cmd = ["${opencodeWrapper}/bin/opencode-entry"];
      WorkingDir = "/home/j_kro";
      Env = [
        "HOME=/home/j_kro"
        "USER=j_kro"
        "PATH=/home/j_kro/.nix-profile/bin:/run/current-system/sw/bin:/usr/bin:/bin"
        "OPENCODE_CONFIG_DIR=/home/j_kro/.opencode"
        "SHELL=/run/current-system/sw/bin/fish"
      ];
      Labels = {
        "org.opencontainers.image.title" = "OpenCode";
        "org.opencontainers.image.description" = "OpenCode AI coding assistant";
        "org.opencontainers.image.version" = "1.2.27";
      };
    };
  }

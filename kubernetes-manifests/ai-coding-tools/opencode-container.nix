{pkgs, ...}: let
  opencodeWrapper = pkgs.writeShellScriptBin "opencode-entry" ''
    #!${pkgs.bash}/bin/bash
    set -e
    export HOME=/home/j_kro
    export USER=j_kro
    export OPENCODE_CONFIG_DIR=/home/j_kro/.opencode
    mkdir -p /home/j_kro/.opencode
    echo "OpenCode container starting..."
    echo "Config: $OPENCODE_CONFIG_DIR"
    exec tail -f /dev/null
  '';
in
  pkgs.dockerTools.buildImage {
    name = "opencode";
    tag = "nixos";
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

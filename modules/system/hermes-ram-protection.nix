{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.hermes-ram-protection;
in {
  options.programs.hermes-ram-protection = {
    enable = lib.mkEnableOption "Hermes RAM protection hooks";
    minFreeRamMB = lib.mkOption {
      type = lib.types.int;
      default = 2048;
      description = "Minimum free RAM in MB required for Hermes operations";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create wrapper scripts in PATH
    environment.systemPackages = with pkgs; [
      (writeScriptBin "hermes-safe-check" ''
        #!/bin/bash
        set -euo pipefail
        if ! /etc/nixos/scripts/hermes-ram-check.sh; then
          exit_code=$?
          if [ $exit_code -eq 1 ]; then
            echo ""
            echo "Operation aborted due to insufficient memory."
            echo "Please free up RAM before running flake checks."
            exit 1
          fi
        fi
        exec nix flake check "$@"
      '')
      (writeScriptBin "hermes-ram-status" ''
        #!/bin/bash
        /etc/nixos/scripts/hermes-ram-check.sh
      '')
    ];

    # Add to justfile as a prerequisite
    environment.etc."just-hermes-ram.just".text = ''
      # Hermes RAM protection
      check-ram:
          @echo "Checking RAM before operation..."
          /etc/nixos/scripts/hermes-ram-check.sh
    '';
  };
}

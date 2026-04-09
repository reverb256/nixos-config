# AI Inference Authentication Module
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.ai-inference.auth;
  inherit (lib) mkIf;
in {
  imports = [
    ./tailscale.nix
    # ./web3.nix  # Future: Web3 + passkey authentication
  ];

  config = mkIf config.services.ai-inference.enable {
    # Authentication is handled in the gateway
    # This module provides supporting configuration

    # API key file validation (if configured)
    # Gateway moved to Kubernetes - removed before dependency
    systemd.services.ai-inference-validate-keys = mkIf (cfg.mode == "api-key" && cfg.apiKeyFile != null) {
      description = "Validate AI inference API keys";
      wantedBy = ["multi-user.target"];
      # Gateway runs in Kubernetes - no before dependency needed

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "ai-inference-validate-keys" ''
          if [ ! -f ${cfg.apiKeyFile} ]; then
            echo "API key file not found: ${cfg.apiKeyFile}"
            exit 1
          fi
          echo "API key file found"
        '';
        User = "root";
      };
    };
  };
}

# Common OpenClaw configuration for all nodes
{ config, lib, pkgs, inputs, ... }:

with lib;

let
  cfg = config.services.openclaw;
  # Common OpenClaw settings for all nodes
  commonSettings = {
    # Use OpenClaw's built-in authentication system
    auth = {
      type = "openclaw";
      # No external authentication needed
    };
    # No model configuration - let OpenClaw handle it
  };
in {
  options.services.openclaw.common = {
    enable = mkEnableOption "Common OpenClaw configuration for all nodes";
  };

  config = mkIf (cfg.enable && cfg.common.enable) {
    # Override OpenClaw settings with common configuration
    services.openclaw.environmentFile = "/run/agenix/openclaw-env";
    services.openclaw.settings = mkMerge [cfg.settings commonSettings];

    # No local LLM services - using cloud providers only
    services.ollama = mkDefault {};

    # Common firewall rules for OpenClaw (if needed)
    networking.firewall = {
      allowedTCPPorts = [8080]; # OpenClaw gateway port
      allowedUDPPorts = [];
    };

    # Add OpenClaw and Ollama to system packages
    environment.systemPackages = with pkgs; [
      inputs.nix-openclaw.packages.x86_64-linux.openclaw-tools
    ];
  };
}
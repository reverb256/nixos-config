# Common OpenClaw configuration for all nodes
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib; let
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
  # Import nix-config.nix to ensure binary caches are available on all nodes
  imports = [./nix-config.nix];

  options.services.openclaw.common = {
    enable = mkEnableOption "Common OpenClaw configuration for all nodes";
  };

  config = mkIf (cfg.enable && cfg.common.enable) {
    # Override OpenClaw settings with common configuration
    services.openclaw.environmentFile = "/run/agenix/openclaw-env";
    services.openclaw.settings = commonSettings;

    # No local LLM services - using cloud providers only
    services.ollama = mkDefault {};

    # Common firewall rules for OpenClaw services
    # NOTE: These are bound to localhost by default for security.
    # Use nginx reverse proxy for external access with SSL/TLS.
    networking.firewall = {
      # Only allow loopback access to OpenClaw services
      # Ports: 18789 (gateway), 18800 (storage MCP)
      interfaces.lo.allowedTCPPorts = [18789 18800];
      allowedUDPPorts = [];
    };

    # Add OpenClaw and Ollama to system packages
    environment.systemPackages = with pkgs; [
      inputs.nix-openclaw.packages.x86_64-linux.openclaw-tools
    ];
  };
}

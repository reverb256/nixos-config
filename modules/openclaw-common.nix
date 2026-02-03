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
in {
  # Import nix-config.nix to ensure binary caches are available on all nodes
  imports = [./nix-config.nix];

  options.services.openclaw.common = {
    enable = mkEnableOption "Common OpenClaw configuration for all nodes";
  };

  config = mkIf cfg.common.enable {
    # Common firewall rules for OpenClaw services
    # NOTE: These are bound to localhost by default for security.
    # Use nginx reverse proxy for external access with SSL/TLS.
    networking.firewall = {
      # Only allow loopback access to OpenClaw services
      # Ports: 18789 (gateway), 18800 (storage MCP)
      interfaces.lo.allowedTCPPorts = [18789 18800];
      allowedUDPPorts = [];
    };

    # No local LLM services - using cloud providers only
    services.ollama = mkDefault {};

    # Add OpenClaw tools to system packages
    environment.systemPackages = with pkgs; [
      inputs.nix-openclaw.packages.x86_64-linux.openclaw-tools
    ];
  };
}

# Common Firewall Ports Module
# Centralized port definitions to prevent conflicts
{
  config,
  lib,
  ...
}:

{
  options.networking.ports = {
    # Monitoring
    monitoring = lib.mkOption {
      type = with lib.types; listOf port;
      default = [9100 9101 9102 9103 9104];
      description = "Prometheus monitoring stack ports";
    };

    # Mining
    mining = lib.mkOption {
      type = with lib.types; listOf port;
      default = [3333 14444];
      description = "Mining operation ports (XMRig, lolminer)";
    };

    # AI/Inference
    ai = lib.mkOption {
      type = with lib.types; listOf port;
      default = [8080 11434];
      description = "AI inference gateway ports";
    };

    # Web
    web = lib.mkOption {
      type = with lib.types; listOf port;
      default = [80 443];
      description = "Standard web ports (HTTP/HTTPS)";
    };

    # File sharing
    fileSharing = lib.mkOption {
      type = with lib.types; listOf port;
      default = [22000 8384];
      description = "Syncthing file sharing ports";
    };
  };

  # This module doesn't directly set firewall ports
  # Instead, it provides port constants for other modules to use
  # Example: networking.firewall.allowedTCPPorts = lib.mkOptionDefault config.networking.ports.monitoring;
}

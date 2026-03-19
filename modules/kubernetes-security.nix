# Kubernetes Security Module
# Runtime security monitoring with Falco

{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.security.kubernetes;
in {
  options.security.kubernetes = {
    enable = mkEnableOption "Kubernetes runtime security monitoring";

    enableFalco = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Falco for runtime threat detection";
    };
  };

  config = mkIf cfg.enable {
    # Install Falco for runtime security monitoring
    services.falco = mkIf cfg.enableFalco {
      enable = true;
      settings = {
        # Falco configuration
        json_output = true;
        log_stderr = true;
        priority = "info";
      };

      # Enable security rules
      rules = [
        # Detect shell in containers (potential compromise)
        "shell_in_containers"
        # Detect sensitive file access
        "sensitive_file_access"
        # Detect privileged container spawns
        "privileged_container"
        # Detect crypto miners
        "crypto_miner"
        # Detect unexpected network connections
        "network_policy"
      ];

      # Output to journald for integration with logging stack
      outputs = [
        {
          type = "syslog";
        }
      ];
    };

    # Install security tools
    environment.systemPackages = with pkgs; [
      falcoctl  # Falco management tool
      kubectl   # For audit scripts
    ];

    # JournalD configuration for security events
    journald.extraConfig = ''
      # Forward security events to persistent storage
      Storage=persistent

      # Increase retention for security audit logs
      SystemMaxUse=2G
      MaxRetentionSec=30day
    '';
  };
}

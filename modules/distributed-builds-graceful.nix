# Distributed Build Configuration with Graceful Degradation
# Enables building across all 4 nodes when available, falls back to conservative local-only when not
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Conservative settings for local-only builds (prevents OOM on 32GB RAM)
  localOnlySettings = {
    max-jobs = 4;  # Safe for single machine with 32GB RAM
    cores = 6;     # Leave headroom for desktop/gaming
  };

  # Aggressive settings when distributed builds are active
  distributedSettings = {
    max-jobs = 21;  # 8 (zephyr) + 6 (nexus) + 3 (forge) + 4 (sentry)
    cores = 8;      # Higher core usage per job since work is distributed
  };
in {
  # ============================================================================
  # CONDITIONAL DISTRIBUTED BUILD CONFIGURATION
  # ============================================================================
  nix = {
    # Only enable distributed builds if build machines are configured and reachable
    distributedBuilds = lib.mkDefault (config.nix.buildMachines != []);

    # Build machines - configured but disabled by default until explicitly enabled
    buildMachines = lib.mkDefault [];

    # Settings that ADAPT based on whether distributed builds are enabled
    settings = {
      # Use substituters on remote builders (download from cache instead of copying)
      builders-use-substitutes = true;

      # Connect timeout for builders (in seconds)
      connect-timeout = 30;

      # Network timeout for slow builders
      download-attempts = 3;

      # ADAPTIVE max-jobs: Conservative when alone, aggressive with builders
      max-jobs = lib.mkDefault (
        if (config.nix.distributedBuilds && config.nix.buildMachines != [])
        then distributedSettings.max-jobs  # 21 jobs with builders
        else localOnlySettings.max-jobs     # 4 jobs local-only
      );

      # ADAPTIVE cores: Same logic
      cores = lib.mkDefault (
        if (config.nix.distributedBuilds && config.nix.buildMachines != [])
        then distributedSettings.cores      # 8 cores with builders
        else localOnlySettings.cores        # 6 cores local-only
      );
    };
  };

  # ============================================================================
  # SSH CONFIGURATION FOR BUILD MACHINES
  # ============================================================================
  programs.ssh.extraConfig = lib.mkIf config.nix.distributedBuilds ''
    # Build machine configurations for distributed Nix builds
    Host nexus
      HostName 10.1.1.120
      User nixbuild
      IdentityFile /home/j_kro/.ssh/id_nixbuild
      ConnectTimeout 5
      StrictHostKeyChecking accept-new
      LogLevel ERROR

    Host forge
      HostName 10.1.1.130
      User nixbuild
      IdentityFile /home/j_kro/.ssh/id_nixbuild
      ConnectTimeout 5
      StrictHostKeyChecking accept-new
      LogLevel ERROR

    Host sentry
      HostName 10.1.1.140
      User nixbuild
      IdentityFile /home/j_kro/.ssh/id_nixbuild
      ConnectTimeout 5
      StrictHostKeyChecking accept-new
      LogLevel ERROR
  '';

  # ============================================================================
  # SSH AGENT CONFIGURATION
  # ============================================================================
  programs.ssh.startAgent = lib.mkDefault config.nix.distributedBuilds;

  # Ensure SSH key directories exist
  systemd.tmpfiles.rules = lib.mkIf config.nix.distributedBuilds [
    "d /home/j_kro/.ssh 0700 j_kro users -"
    "d /home/nixbuild/.ssh 0700 nixbuild nixbuild -"
  ];

  # ============================================================================
  # BUILD OPTIMIZATION
  # ============================================================================
  # Enable automatic GC to prevent disk space issues
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Optimize store after builds
  nix.settings.auto-optimise-store = true;

  # ============================================================================
  # HELPER SCRIPT TO TOGGLE DISTRIBUTED BUILDS
  # ============================================================================
  environment.systemPackages = lib.mkIf config.nix.distributedBuilds [
    (pkgs.writeScriptBin "nix-toggle-distributed" ''
      #!/usr/bin/env bash
      # Toggle distributed builds on/off
      
      if [ "$1" == "on" ]; then
        echo "Enabling distributed builds..."
        sudo mkdir -p /etc/nix
        echo '{ nix.buildMachines = [ ... ]; }' | sudo tee /etc/nix/local-distributed.nix
        echo "Run 'sudo nixos-rebuild switch' to apply"
      elif [ "$1" == "off" ]; then
        echo "Disabling distributed builds..."
        sudo rm -f /etc/nix/local-distributed.nix
        echo "Run 'sudo nixos-rebuild switch' to apply"
      else
        echo "Usage: nix-toggle-distributed [on|off]"
        echo ""
        echo "Current status:"
        systemctl --user status nix-daemon 2>/dev/null | head -3
      fi
    '')
  ];
}

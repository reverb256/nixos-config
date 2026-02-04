# Distributed Build Configuration
# Enables building across all 4 nodes in the cluster (51 cores total)
# See AGENTS.md for cluster architecture details
{
  lib,
  ...
}: {
  # ============================================================================
  # DISTRIBUTED BUILD CONFIGURATION
  # ============================================================================
  nix = {
    # DISABLED: Distributed builds causing signature/copying issues
    distributedBuilds = false;

    # Build machines - EMPTY (disabled)
    buildMachines = [];

    # Settings for distributed builds
    settings = {
      # Use substituters on remote builders (download from cache instead of copying)
      builders-use-substitutes = true;

      # Maximum number of parallel build jobs across all machines
      # Use mkDefault to allow host-specific overrides
      max-jobs = lib.mkDefault 21; # 8 (zephyr) + 6 (nexus) + 3 (forge) + 4 (sentry)

      # Connect timeout for builders (in seconds)
      connect-timeout = 30;
    };
  };

  # ============================================================================
  # SSH CONFIGURATION FOR BUILD MACHINES
  # ============================================================================
  programs.ssh.extraConfig = ''
    # Build machine configurations for distributed Nix builds
    Host nexus
      HostName 192.168.100.X
      User nixbuild
      IdentityFile /home/j_kro/.ssh/id_nixbuild
      ConnectTimeout 5
      StrictHostKeyChecking accept-new
      LogLevel ERROR

    Host forge
      HostName 192.168.100.X
      User nixbuild
      IdentityFile /home/j_kro/.ssh/id_nixbuild
      ConnectTimeout 5
      StrictHostKeyChecking accept-new
      LogLevel ERROR

    Host sentry
      HostName 192.168.100.X
      User nixbuild
      IdentityFile /home/j_kro/.ssh/id_nixbuild
      ConnectTimeout 5
      StrictHostKeyChecking accept-new
      LogLevel ERROR
  '';

  # ============================================================================
  # SSH AGENT CONFIGURATION
  # ============================================================================
  programs.ssh.startAgent = true;

  # Ensure SSH key exists and has correct permissions
  systemd.tmpfiles.rules = [
    "d /home/j_kro/.ssh 0700 j_kro users -"
    "d /home/nixbuild/.ssh 0700 nixbuild nixbuild -"
  ];

  # ============================================================================
  # BUILD OPTIMIZATION
  # ============================================================================
  # Enable automatic GC to prevent disk space issues on builders
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # Optimize store after builds
  nix.settings.auto-optimise-store = true;
}

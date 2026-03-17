# Distributed Build Configuration
# Enables building across nodes in the cluster
{
  lib,
  config,
  pkgs,
  ...
}: let
  currentHost = config.networking.hostName or "unknown";
in {
  nix = {
    distributedBuilds = lib.mkDefault true;

    settings = {
      builders-use-substitutes = true;
      require-sigs = lib.mkForce false;
      trusted-users = lib.mkForce ["root" "*" "@wheel"];

      substituters = lib.mkAfter [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://cache.garnix.io"
        "https://reverb-os.cachix.org"
        "https://ezkea.cachix.org"
        "https://nix-gaming.cachix.org"
        "https://cache.nixos-cuda.org"
      ];
      trusted-public-keys = lib.mkAfter [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
        "reverb-os.cachix.org-1:dctKtu02bV/4fbsYbGuVVxQo9R7X6lNqUet1qj2jYzI="
        "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
        "nix-gaming.cachix.org-1:vn/szNT7r/Pc1FbcBjRGHLk7XNk0v2KvMq2v7EwXQ8w="
        "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
      ];

      cores = lib.mkForce (
        if currentHost == "zephyr" then 4
        else if currentHost == "nexus" then 4
        else if currentHost == "sentry" then 2
        else if currentHost == "forge" then 2
        else 4
      );

      max-jobs = lib.mkForce (
        if currentHost == "zephyr" then 4
        else if currentHost == "nexus" then 6
        else if currentHost == "sentry" then 4
        else if currentHost == "forge" then 1
        else 2
      );

      http-connections = 100;
      connect-timeout = 30;
      max-silent-time = 3600;
      keep-build-log = true;
      log-lines = 2000;
    };
  };

  programs.ssh.startAgent = true;

  systemd.services.copy-build-ssh-key = {
    description = "Copy SSH key for distributed builds";
    wantedBy = ["multi-user.target"];
    after = ["local-fs.target"];
    before = ["nix-daemon.service"];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    script = ''
      if [ ! -f /etc/nixos/ssh/id_ed25519 ]; then
        install -m 600 /home/j_kro/.ssh/id_ed25519 /etc/nixos/ssh/id_ed25519
        install -m 644 /home/j_kro/.ssh/id_ed25519.pub /etc/nixos/ssh/id_ed25519.pub
      fi
    '';
  };

  environment.etc = {
    "ssh/ssh_config.d/50-build-machines.conf".text = ''
      Host zephyr nexus forge sentry
        User j_kro
        IdentityFile /etc/nixos/ssh/id_ed25519
        IdentitiesOnly yes
        StrictHostKeyChecking accept-new
        ConnectTimeout 30
    '';

    "nix/machines".text = let
      machines = [
        {
          hostName = "zephyr";
          system = "x86_64-linux";
          sshUser = "j_kro";
          sshKey = "/etc/nixos/ssh/id_ed25519";
          maxJobs = 4;
          speedFactor = 8;
          supportedFeatures = ["kvm" "big-parallel"];
          mandatoryFeatures = [];
        }
        {
          hostName = "forge";
          system = "x86_64-linux";
          sshUser = "j_kro";
          sshKey = "/etc/nixos/ssh/id_ed25519";
          maxJobs = 1;
          speedFactor = 2;
          supportedFeatures = ["big-parallel"];
          mandatoryFeatures = [];
        }
        {
          hostName = "sentry";
          system = "x86_64-linux";
          sshUser = "j_kro";
          sshKey = "/etc/nixos/ssh/id_ed25519";
          maxJobs = 4;
          speedFactor = 3;
          supportedFeatures = ["big-parallel"];
          mandatoryFeatures = [];
        }
      ];
      formatMachine = m: ''
        ssh-ng://${m.sshUser}@${m.hostName} ${m.system} ${if m.sshKey != null then m.sshKey else "-"} ${toString m.maxJobs} ${toString m.speedFactor} ${lib.concatStringsSep "," m.supportedFeatures} ${lib.concatStringsSep "," m.mandatoryFeatures}
      '';
    in lib.concatMapStrings formatMachine machines;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  nix.settings.auto-optimise-store = true;

  # ============================================================================
  # CCACHE - 20GB compiler cache for faster rebuilds
  # ============================================================================
  # Cache directory: /var/cache/ccache (persistent, not on tmpfs)
  # Size: 20GB (~500K-1M cached compiler objects)
  # Shared across: GCC, Clang, and any compiler supporting CCACHE_PATH

  # Enable ccache in Nix sandbox (allows builds to access cache directory)
  nix.settings.extra-sandbox-paths = ["/var/cache/ccache"];

  # Set 20GB cache size and configure ccache behavior via environment
  environment.variables = {
    CCACHE_DIR = "/var/cache/ccache";
    CCACHE_SIZE = "20G";
    CCACHE_COMPRESS = "1";
    CCACHE_COMPRESSLEVEL = "6";
    CCACHE_MAXFILES = "1000000";
    CCACHE_DIRLEVELS = "3";
    CCACHE_LOGFILE = "/var/log/ccache.log";
  };

  # Consolidated tmpfiles rules (SSH keys + ccache directories)
  systemd.tmpfiles.rules = [
    # SSH key directories for distributed builds
    "d /home/j_kro/.ssh 0700 j_kro users -"
    "d /root/.ssh 0700 root root -"
    "d /etc/nixos/ssh 0755 root root -"
    # ccache cache directory and log file
    "d /var/cache/ccache 0755 root root -"
    "f /var/log/ccache.log 0644 root root -"
  ];

  # Ensure ccache is in PATH for all users
  environment.systemPackages = with pkgs; [ccache];
}

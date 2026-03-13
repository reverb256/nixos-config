# Common Host Defaults - Shared settings for all cluster nodes
# This module provides consistent defaults across all hosts
# Host-specific overrides should be placed in hosts/<hostname>/configuration.nix
{
  config,
  lib,
  pkgs,
  ...
}: {
  # ============================================================================
  # SYSTEM STATE VERSION
  # ============================================================================
  # All hosts use the same state version for consistency
  system.stateVersion = "26.05";

  # ============================================================================
  # TIME ZONE - CLUSTER STANDARD
  # ============================================================================
  # All cluster nodes use UTC for consistent logging and to avoid DST issues
  # This is a default; individual nodes can override if needed
  time.timeZone = lib.mkDefault "UTC";

  # ============================================================================
  # SERVICES CONFIGURATION
  # ============================================================================
  services = {
    # SSH CERTIFICATE AUTHORITY - Enable cluster-wide SSO
    ssh-ca.enable = lib.mkDefault true;
    # LOGIND CONFIGURATION & POWER MANAGEMENT - DISABLE ALL SUSPEND/SLEEP/AUTO-SHUTDOWN
    # Prevent user processes from being killed on logout
    # These settings prevent the system from automatically suspending, sleeping,
    # or hibernating. Cluster nodes must remain available at all times.
    logind.settings = {
      Login = {
        # Prevent user processes from being killed on logout
        # This is important for background services and tmux/screen sessions
        KillUserProcesses = lib.mkDefault false;

        # Disable automatic suspend on lid close (for laptops/notebooks)
        HandleLidSwitch = "ignore";
        HandleLidSwitchExternalPower = "ignore";

        # Disable automatic suspend on power button press
        HandlePowerKey = "ignore";

        # Disable suspend key action
        HandleSuspendKey = "ignore";

        # Disable hibernate key action
        HandleHibernateKey = "ignore";

        # Explicitly inhibit idle actions
        IdleAction = "ignore";
        IdleActionSec = "0";

        # Don't suspend when lid is closed
        HoldoffTimeoutSec = "0";
      };
    };

    # DISPLAY MANAGER DEFAULTS
    # Consistent display manager configuration across all hosts
    displayManager = {
      sddm = {
        enable = lib.mkDefault true;
        wayland.enable = lib.mkDefault true;
      };
      defaultSession = lib.mkDefault "plasma";
      autoLogin = {
        enable = lib.mkDefault true;
        user = lib.mkDefault "j_kro";
      };
    };

    # SPEECH-TO-TEXT DICTATION
    # Available on all desktop hosts with audio input
    whisper-dictation = lib.mkDefault {
      enable = true;
      model = "base.en";
      language = "en";
      injectionMode = "both";
      keyDelay = 10;
      notify = true;
      silenceTimeout = 1.5;
      silenceThreshold = "5%";
    };

    # BACKUP TO GARAGE S3
    # Automated backups to Garage cluster (disabled by default, enable on backup node)
    # Enable on Zephyr: services.backup-to-garage.enable = true;
    backup-to-garage.enable = lib.mkDefault false;
  };

  # ============================================================================
  # NIX SETTINGS
  # ============================================================================
  # Configure Nix daemon settings for distributed builds
  nix.settings = {
    # Trusted users required for distributed builds across cluster
    # Without this, remote build users cannot access the Nix store
    trusted-users = ["j_kro"];

    # Binary cache substituters - check local Harmonia cache first
    substituters = lib.mkOptionDefault [
      "http://zephyr.tigris-ule.ts.net:50000?trusted=1"
    ];

    # System features - declare x86-64-v3 microarchitecture support
    # This allows building v3-optimized packages (gccarch-x86-64-v3)
    # All cluster CPUs support AVX2: Zen 3 (Zephyr), Zen 2 (Nexus),
    # Coffee Lake (Forge), Zen 1 (Sentry with AVX2)
    # Use mkAfter to append to the default system-features list
    system-features = lib.mkAfter ["gccarch-x86-64-v3"];

    # Fallback to public caches if local cache miss
    # https://cache.nixos.org
  };

  # ============================================================================
  # BOOTLOADER DEFAULTS
  # ============================================================================
  # systemd-boot configuration for all hosts
  boot.loader = {
    # Enable systemd-boot by default (UEFI systems)
    systemd-boot.enable = lib.mkDefault true;

    # Allow touching EFI variables (required for boot management)
    efi.canTouchEfiVariables = lib.mkDefault true;

    # GRACEFUL BOOT ENTRY MANAGEMENT
    # When false, systemd-boot will remove old entries aggressively
    # This prevents accumulation of 75+ old generations on the ESP
    # When true (default), old entries are kept for rollback safety
    systemd-boot.graceful = lib.mkDefault false;
  };

  # ============================================================================
  # KERNEL DEFAULTS
  # ============================================================================
  # Use Zen kernel by default for better desktop responsiveness
  # Individual hosts can override if needed
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_zen;

  # ============================================================================
  # KUBERNETES FIREWALL DEFAULTS
  # ============================================================================
  # Kubernetes networking requirements for all cluster nodes
  # These ports are required for Kubernetes cluster communication
  networking.firewall = {
    # NodePort range - required for Kubernetes Services of type NodePort
    # This range is the Kubernetes default and should be consistent across all nodes
    allowedTCPPortRanges = lib.mkOptionDefault [
      {
        from = 30000;
        to = 32767;
      }
    ];

    # Flannel VXLAN - required for pod-to-pod networking
    allowedUDPPorts = lib.mkOptionDefault [
      8472 # Flannel VXLAN
    ];
  };

  # ============================================================================
  # PROGRAMS - PLATFORM DEFAULTS
  # ============================================================================
  # Enable sleepy-launcher to prevent automatic sleep/suspend
  # Git configuration across all cluster nodes
  # Enable nix-ld for better binary compatibility
  programs = {
    sleepy-launcher.enable = lib.mkDefault true;
    git = {
      enable = lib.mkDefault true;
      config = {
        init.defaultBranch = "main";
        user.name = "j_kro";
        user.email = lib.mkDefault "j_kro@${config.networking.hostName or "cluster"}";
      };
    };
    nix-ld.enable = lib.mkDefault true;
  };
}

# ==============================================================================
# COMMON HOST DEFAULTS
# ==============================================================================
# Shared settings for all cluster nodes in the NixOS cluster
#
# Purpose: Provides consistent defaults across all hosts (Zephyr, Nexus, Forge, Sentry)
# Location: /etc/nixos/modules/common-host-defaults.nix
#
# Overriding Defaults:
# - Use lib.mkDefault for optional settings (allows host-specific override)
# - Use lib.mkOptionDefault for list/attribute set merging
# - Place host-specific overrides in hosts/<hostname>/configuration.nix
#
# Table of Contents:
# 1. System State Version
# 2. Time Zone
# 3. Services Configuration
#    3.1 SSH Certificate Authority
#    3.2 Logind & Power Management
#    3.3 Display Manager
#    3.4 Speech-to-Text Dictation
#    3.5 Backup Services
#    3.6 Compute Workload Monitor
# 4. Nix Settings
# 5. Bootloader Defaults
# 6. Kernel Defaults
# 7. Kubernetes Firewall Defaults
# 8. Programs - Platform Defaults
# ==============================================================================
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
  # User sessions see local time (America/Winnipeg) via environment.sessionVariables
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

    # RCLONE CLOUD STORAGE SYNC
    # Sync with 70+ cloud providers (S3, Google Drive, OneDrive, Dropbox, Box, Mega, B2, etc.)
    # Example configuration:
    #   rclone-sync.enable = true;
    #   rclone-sync.remotes.garage.type = "s3";
    #   rclone-sync.remotes.garage.endpoint = "http://10.1.1.110:3900";
    #   rclone-sync.remotes.garage.accessKeyId = "GKac91d924fc76a30b9bcf6c3e";
    #   rclone-sync.remotes.garage.secretAccessKey = ""; # Use agenix!
    #   rclone-sync.syncJobs = [
    #     { name = "garage-to-onedrive"; source = "garage:backups"; destination = "onedrive:backups"; }
    #   ];
    rclone-sync.enable = lib.mkDefault false;

    # COMPUTE WORKLOAD MONITOR
    # Autonomous GPU workload detection and profile management
    # Detects build workloads via PSI (Pressure Stall Information) and pauses mining
    # Uses hysteresis to prevent thrashing between states
    compute-workload-monitor = lib.mkDefault {
      enable = true;
      checkInterval = 10; # Check every 10 seconds
    };
  };

  # ============================================================================
  # HARDWARE CONFIGURATION
  # ============================================================================
  # GPU COMPUTE - Vulkan and CUDA support for AI inference
  # Vulkan provides universal GPU backend for llama.cpp, PyTorch, etc.
  # Works on NVIDIA, AMD, and Intel GPUs with ~85-95% of CUDA performance
  # CUDA provides native NVIDIA GPU support for maximum performance
  hardware.gpu-compute.enable = lib.mkDefault true;
  hardware.gpu-compute.vulkan.enable = lib.mkDefault true;
  hardware.gpu-compute.cuda.enable = lib.mkDefault true;

  # ============================================================================
  # NIX SETTINGS
  # ============================================================================
  # Configure Nix daemon settings for distributed builds
  nix.settings = {
    # Trusted users required for distributed builds across cluster
    # Without this, remote build users cannot access the Nix store
    trusted-users = ["j_kro"];

    # Fallback to public caches if local cache miss
    # https://cache.nixos.org
  };

  # ============================================================================
  # BOOTLOADER DEFAULTS
  # ============================================================================
  # systemd-boot configuration for all hosts
  # Includes security hardening, boot counting, and recovery tools
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

    # GENERATION LIMIT - Keep boot menu manageable
    # Limits the number of generations shown in boot menu
    # 20 generations = ~1MB on ESP vs ~50MB with unlimited
    # Older generations remain accessible via nixos-rebuild --rollback
    systemd-boot.configurationLimit = lib.mkDefault 20;

    # SECURITY: Disable editor to prevent root access via init=/bin/sh
    # Set to true temporarily if you need to debug boot issues
    systemd-boot.editor = lib.mkDefault false;

    # RECOVERY & DEBUGGING TOOLS
    # EDK2 UEFI Shell - for firmware debugging and manual boot recovery
    # Accessible from boot menu if system won't boot
    systemd-boot.edk2-uefi-shell.enable = lib.mkDefault true;

    # MemTest86+ - memory testing without separate boot media
    # Useful for diagnosing RAM issues without Live USB
    systemd-boot.memtest86.enable = lib.mkDefault true;

    # BOOT COUNTING - Automatic rollback on boot failures
    # DISABLED: systemd-boot doesn't recognize boot-count options
    # Use systemd-boot's built-in automatic fallback instead
    # systemd-boot.extraInstallCommands = ''
    #   # Add boot-count fields to all NixOS entries for automatic rollback
    #   # Use full paths for grep/sed to work in builds where PATH is limited
    #   for entry in /boot/loader/entries/nixos-generation-*.conf; do
    #     # Don't modify already-modified entries or specialisation entries
    #     ${pkgs.gnugrep}/bin/grep -q "boot-count" "$entry" && continue
    #     ${pkgs.gnugrep}/bin/grep -q "specialisation" "$entry" && continue
    #
    #     # Add boot counting: try entry, fallback after 3 failed boots
    #     # This is appended after the 'options' line for proper placement
    #     ${pkgs.gnused}/bin/sed -i '/^options/a boot-count try\nboot-count-min-success 3' "$entry"
    #   done
    # '';
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

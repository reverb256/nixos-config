# Common Host Defaults - Shared settings for all cluster nodes
# This module provides consistent defaults across all hosts
# Host-specific overrides should be placed in hosts/<hostname>/configuration.nix
{lib, ...}: {
  # ============================================================================
  # SYSTEM STATE VERSION
  # ============================================================================
  # All hosts use the same state version for consistency
  system.stateVersion = "26.05";

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
  };

  # Enable sleepy-launcher to prevent automatic sleep/suspend
  # This creates a systemd inhibitor that tells the system not to sleep
  programs.sleepy-launcher.enable = lib.mkDefault true;

  # ============================================================================
  # NIX SETTINGS
  # ============================================================================
  # Configure Nix daemon settings for distributed builds
  nix.settings = {
    # Trusted users required for distributed builds across cluster
    # Without this, remote build users cannot access the Nix store
    trusted-users = ["j_kro"];
  };
}

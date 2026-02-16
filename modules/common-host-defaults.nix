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
  # LOGIND CONFIGURATION
  # ============================================================================
  # Prevent user processes from being killed on logout
  # This is important for background services and tmux/screen sessions
  services.logind.settings.Login.KillUserProcesses = lib.mkDefault false;

  # ============================================================================
  # DISPLAY MANAGER DEFAULTS
  # ============================================================================
  # Consistent display manager configuration across all hosts
  services.displayManager = {
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
}

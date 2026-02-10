# ============================================================================
# SSH CONFIGURATION FOR ROOT - Round-trip distributed builds
# ============================================================================
# This module configures SSH keys and config for root user to enable
# distributed builds across the cluster when running nixos-rebuild with sudo
# ============================================================================
{
  lib,
  pkgs,
  config,
  ...
}:
with lib; {
  options.root-ssh = {
    enable = mkEnableOption "Enable SSH configuration for root user";

    nixbuildKey = mkOption {
      type = types.path;
      description = "Path to nixbuild SSH private key for distributed builds";
      default = pkgs.writeText "id_nixbuild" "";
    };

    knownHosts = mkOption {
      type = types.lines;
      description = "SSH known hosts for cluster nodes";
      default = "";
    };
  };

  config = mkIf config.root-ssh.enable {
    # ============================================================================
    # ROOT USER SSH CONFIGURATION
    # ============================================================================
    users.users.root = {
      openssh = {
        authorizedKeys.keys = [
          # j_kro's zephyr key for cluster access
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKxlZFnzslRkCM+6mEdPpgLDudCRHYdeEcJoAPLDmHvm j_kro@zephyr"
        ];
      };

      # Ensure SSH directory exists with correct permissions
      # Note: Using systemd.tmpfiles for runtime directory creation
    };

    # Create root SSH directories and files via systemd tmpfiles
    systemd.tmpfiles.rules = [
      # Create SSH directory structure for root
      "d /root/.ssh 0700 root root -"
      "d /root/.ssh/sockets 0700 root root -"

      # Copy nixbuild SSH key from j_kro's directory
      # This assumes the key is already in j_kro's .ssh directory
      "C /root/.ssh/id_nixbuild 0600 root root - /home/j_kro/.ssh/id_nixbuild"
      "C /root/.ssh/id_nixbuild.pub 0644 root root - /home/j_kro/.ssh/id_nixbuild.pub"
    ];

    # ============================================================================
    # SSH CLIENT CONFIGURATION FOR ROOT
    # ============================================================================
    environment.etc."ssh/root_config" = {
      # Alternative config file for root user (not used by default)
      enable = false;
    };

    # Note: /root/.ssh/config is managed by manual setup because
    # environment.etc."ssh/config" is for all users, not root-specific
    # The root SSH config is created via systemd tmpfiles or manual setup
    # See: AGENTS.md for manual setup instructions
  };
}

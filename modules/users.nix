# ============================================================================
# USER MANAGEMENT - Accounts, groups, sudo rules, and permissions
# ============================================================================
{
  pkgs,
  lib,
  ...
}:
with lib; {
  # ============================================================================
  # USER ACCOUNTS
  # ============================================================================
  users = {
    # Main user account
    users.j_kro = {
      isNormalUser = true;
      description = "j_kro";
      extraGroups = [
        "wheel"
        "networkmanager"
        "video"
        "input"
        "dialout"
        "libinput"
        "render"
        "plugdev"
        "tailscale"
      ];
      shell = "/run/current-system/sw/bin/fish";
      packages = with pkgs; [
        just
        fzf
        (kdePackages.kate.overrideAttrs (previousAttrs: {
          # Add pipewire to buildInputs to fix pipewire-0.3 library errors
          # This is required for Qt6 multimedia integration with PipeWire
          buildInputs = previousAttrs.buildInputs ++ [pipewire];
        }))
        steam
      ];
      openssh.authorizedKeys.keys = [
        # Zephyr current key (as of 2026-01-31)
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKxlZFnzslRkCM+6mEdPpgLDudCRHYdeEcJoAPLDmHvm j_kro@zephyr"
        # Forge unified cluster key
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILLLCzj+9HECcMChcD92fW6nChnSX1VEBw8WPFwvlRJH j_kro@cluster"
        # Sentry keys
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILGuU7xfwpno/Bcf9olU4WfdmlzWPCQUuaIPBzSK8kmH j_kro@zephyr"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPY8U4+NjQh0XwLVYF2yVQHuIVoujWC8zjB8K7W6hNQx j_kro@sentry"
        # Nexus cluster key
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFGFHqWyZE0fadxRlfCFf/hyahjiS9WzlIvLkYf0ZK9b j_kro@nixos-cluster"
        # Root keys for cluster access
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFvsktMT9/yhSZryFJp688+SsYPwnZdyAWaUhRS9L4jM root@cluster"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDCtXll62kA3CTH3NXDDtVt6W621actl6+cQPUg9YnDN root@nexus"
        # Distributed build key (matches ~/.ssh/id_nixbuild.pub)
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBrQ6cTBLsgw8N2xKu6S3p7mlBiicKRL39QflEKaJvDl nix-distributed-build"
        # Reverb256 CA
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILM8m4+tHYj152DRz2bXuv6PrSpC201yYN8Svb5DXEiC j_kroeker@reverb256.ca"
      ];
    };

    # Mining user for secure mining operations
    users.mining = {
      isSystemUser = true;
      group = "mining";
      description = "Mining services user";
      extraGroups = [
        "video" # GPU access
        "render" # GPU rendering access
        "dialout" # Serial port access for mining devices
        "input" # Input device access
        "plugdev" # USB device access
      ];
      home = "/var/lib/mining";
      createHome = true;
      shell = "/bin/bash";
    };

    # Mining group
    groups.mining = {};

    # Nix build group for distributed builds
    groups.nixbuild = {};

    # Plugdev group for USB device access (used by gaming.nix udev rules)
    groups.plugdev = {};

    # Tailscale group for SSH access between nodes
    groups.tailscale = {};

    # Lobster group for AI assistant
    groups.lobster = {};

    # ============================================================================
    # LOBSTER USER - AI Assistant Service 🦞
    # ============================================================================
    # NOTE: This is a system service user, not a login user.
    # The actual service user configuration is in modules/openclaw.nix
    # We only define the group here and let the modules handle the user.
    # This prevents conflicts between different module definitions.

    # ============================================================================
    # NIX BUILD USER FOR DISTRIBUTED BUILDS
    # ============================================================================
    users.nixbuild = {
      isSystemUser = true;
      group = "nixbuild";
      description = "Nix build user for distributed builds";
      extraGroups = ["nixbuild"];
      home = "/var/empty";
      createHome = false;
      shell = "/run/current-system/sw/bin/bash";
      openssh.authorizedKeys.keys = [
        # Cluster-wide distributed build key (legacy)
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBrQ6cTBLsgw8N2xKu6S3p7mlBiicKRL39QflEKaJvDl nix-distributed-build"
        # j_kro@zephyr SSH key (current)
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKxlZFnzslRkCM+6mEdPpgLDudCRHYdeEcJoAPLDmHvm j_kro@zephyr"
      ];
    };
  };

  # ============================================================================
  # SUDO CONFIGURATION
  # ============================================================================
  security.sudo = {
    # Passwordless sudo for wheel group (security risk - for mining controls)
    wheelNeedsPassword = false;

    # NOTE: Lobster (AI service user) has NO sudo access by design.
    # It runs as a restricted system user with only service permissions.
    # See modules/openclaw.nix for the service configuration.
    extraRules = [
      # Allow j_kro to control mining services without password (for desktop icons)
      {
        users = ["j_kro"];
        commands = [
          {
            command = "/run/current-system/sw/bin/systemctl start lolminer-nvidia.service";
            options = ["NOPASSWD"];
          }
          {
            command = "/run/current-system/sw/bin/systemctl stop lolminer-nvidia.service";
            options = ["NOPASSWD"];
          }
          {
            command = "/run/current-system/sw/bin/systemctl start xmrig.service";
            options = ["NOPASSWD"];
          }
          {
            command = "/run/current-system/sw/bin/systemctl stop xmrig.service";
            options = ["NOPASSWD"];
          }
          {
            command = "/run/current-system/sw/bin/systemctl status lolminer-nvidia.service";
            options = ["NOPASSWD"];
          }
          {
            command = "/run/current-system/sw/bin/systemctl status xmrig.service";
            options = ["NOPASSWD"];
          }
        ];
      }
      {
        # Allow mining user to run nvidia-smi without password for GPU management
        users = ["mining"];
        commands = [
          {
            command = "/run/current-system/sw/bin/nvidia-smi";
            options = ["NOPASSWD"];
          }
        ];
      }

      {
        # Allow j_kro to run docker commands without password (for containers)
        users = ["j_kro"];
        commands = [
          {
            command = "/run/current-system/sw/bin/docker";
            options = ["NOPASSWD"];
          }
          {
            command = "/run/current-system/sw/bin/docker ps";
            options = ["NOPASSWD"];
          }
          {
            command = "/run/current-system/sw/bin/docker images";
            options = ["NOPASSWD"];
          }
          {
            command = "/run/current-system/sw/bin/docker logs";
            options = ["NOPASSWD"];
          }
          {
            command = "/run/current-system/sw/bin/docker exec";
            options = ["NOPASSWD"];
          }
        ];
      }
    ];
  };

  # ============================================================================
  # NIX SETTINGS - User-specific permissions
  # ============================================================================
  nix.settings.trusted-users = ["root" "j_kro"];

  # ============================================================================
  # SHELL CONFIGURATION
  # ============================================================================
  programs.fish = {
    enable = true;
    vendor = {
      completions.enable = true;
      config.enable = true;
      functions.enable = true;
    };
  };

  # Ignore shell program check for j_kro user
  users.users.j_kro.ignoreShellProgramCheck = true;
}

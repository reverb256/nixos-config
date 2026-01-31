# ============================================================================
# USER MANAGEMENT - Accounts, groups, sudo rules, and permissions
# ============================================================================
{pkgs, ...}: {
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
        "nixbld" # Required for building with Nix daemon
      ];
      shell = "/run/current-system/sw/bin/fish";
      packages = with pkgs; [
        just
        fzf
        kdePackages.kate
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

    # OpenClaw group for AI assistant
    groups.lobster = {};

    # ============================================================================
    # LOBSTER USER - OpenClaw AI Assistant 🦞
    # ============================================================================
    users.lobster = {
      isNormalUser = true;
      description = "🦞 OpenClaw AI Assistant";
      extraGroups = [
        "wheel"
        "lobster"
        "docker"
        "video"
        "render"
        "networkmanager"
        "nixbld" # Required for Nix builds
      ];
      home = "/home/lobster";
      createHome = true;
      shell = "/run/current-system/sw/bin/fish";
      openssh.authorizedKeys.keys = [
        # Zephyr current key
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
        # Reverb256 CA
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILM8m4+tHYj152DRz2bXuv6PrSpC201yYN8Svb5DXEiC j_kroeker@reverb256.ca"
        # OpenClaw cluster key for Reverb-OS
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFyCNsbhrGynnbLpS56JQDXJJ0QV1mgudaW6+2AvHjdu openclaw-cluster"
      ];
    };

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
      shell = "/bin/bash";
      openssh.authorizedKeys.keys = [
        # Cluster-wide distributed build key
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBrQ6cTBLsgw8N2xKu6S3p7mlBiicKRL39QflEKaJvDl nix-distributed-build"
      ];
    };
  };

  # ============================================================================
  # SUDO CONFIGURATION
  # ============================================================================
  security.sudo = {
    # Passwordless sudo for wheel group (security risk - for mining controls)
    wheelNeedsPassword = false;

    # Lobster (OpenClaw) gets FULL SYSTEM ACCESS - can run any command
    extraRules = [
      {
        users = ["lobster"];
        commands = [
          {
            command = "ALL";
            options = ["NOPASSWD" "SETENV"];
          }
        ];
      }
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
      # Allow mining user to run nvidia-smi without password for GPU management
      {
        users = ["mining"];
        commands = [
          {
            command = "/run/current-system/sw/bin/nvidia-smi";
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

# ============================================================================
# USER MANAGEMENT - Accounts, groups, sudo rules, and permissions
# ============================================================================
{
  config,
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
        "uinput"
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

    # Uinput group for virtual input devices (ydotool)
    groups.uinput = {};

    # ============================================================================
    # LOBSTER USER - AI Assistant Service 🦞
    # ============================================================================
    # NOTE: This is a system service user, not a login user.
    # We only define the group here and let the module handle the user.
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
    # Require password for wheel group (security improvement)
    # Specific NOPASSWD rules below for commonly-used commands
    wheelNeedsPassword = false;

    # Preserve SSH_AUTH_SOCK for distributed builds with sudo
    # This allows SSH agent forwarding when running nixos-rebuild with sudo
    extraConfig = ''
      Defaults env_keep += "SSH_AUTH_SOCK"
      Defaults env_keep += "SSH_AGENT_PID"
      # Reduce password timeout for security (5 min instead of default 15)
      Defaults timestamp_timeout = 5
    '';

    # NOTE: Lobster (AI service user) has NO sudo access by design.
    # It runs as a restricted system user with only service permissions.
    extraRules =
      [
        # Allow j_kro to control systemd services without password (for desktop icons/plasmoid)
        # Using /run/wrappers/bin/sudo path which is the actual sudo on NixOS
        {
          users = ["j_kro"];
          commands = [
            {
              # Allow all systemctl commands for service management
              command = "${pkgs.systemd}/bin/systemctl *";
              options = ["NOPASSWD"];
            }
            {
              # NixOS rebuild commands (commonly used)
              command = "${pkgs.nixos-rebuild}/bin/nixos-rebuild *";
              options = ["NOPASSWD"];
            }
            {
              # Colmena deployment (nix run .#colmena)
              command = "/nix/store/*/bin/colmena *";
              options = ["NOPASSWD"];
            }
            {
              # nix run commands for deployment
              command = "${pkgs.nix}/bin/nix run *";
              options = ["NOPASSWD"];
            }
          ];
        }
        {
          # Allow j_kro to run podman commands without password (podman is rootless by default)
          users = ["j_kro"];
          commands = [
            {
              command = "${pkgs.podman}/bin/podman *";
              options = ["NOPASSWD"];
            }
          ];
        }
      ]
      ++ lib.optionals (config.hardware.nvidia ? package && config.hardware.nvidia.package != null) [
        {
          # Allow mining user to run nvidia-smi without password for GPU management
          # Only included when NVIDIA is enabled
          users = ["mining"];
          commands = [
            {
              command = "${config.hardware.nvidia.package.bin}/bin/nvidia-smi *";
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

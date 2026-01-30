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
      ];
      shell = pkgs.fish;
      packages = with pkgs; [
        just
        fzf
        kdePackages.kate
        steam
      ];
      openssh.authorizedKeys.keys = [
        # Zephyr keys (2 different keys from this host)
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM2sHH/zyVSvk4pZPr3dcMEiG8rtgnf+AbMNIqk5r6Qd j_kro@zephyr"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHE2FZVCG9Wyk1LzjwFMI7usfyFmPCl+uLeq7hg/dB3S j_kro@zephyr"
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
        # Distributed build key
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILIs8j7w+YBwwvG5P2wRvoojMGDPUZinUqcW/hBKb3Vl nix-distributed-build"
        # Reverb256 CA
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILM8m4+tHYj152DRz2bXuv6PrSpC201yYN8Svb5DXEiC j_kroeker@reverb256.ca"
      ];
    };

    # Mining user for secure mining operations
    users.mining = {
      isSystemUser = true;
      group = "mining";
      description = "Mining services user";
      extraGroups = ["video" "dialout" "input"];
      home = "/var/lib/mining";
      createHome = true;
      shell = "/bin/false";
    };

    # Mining group
    groups.mining = {};

    # Plugdev group for USB device access (used by gaming.nix udev rules)
    groups.plugdev = {};
  };

  # ============================================================================
  # SUDO CONFIGURATION
  # ============================================================================
  security.sudo = {
    # Passwordless sudo for wheel group (security risk - for mining controls)
    wheelNeedsPassword = false;

    # Allow j_kro to control mining services without password (for desktop icons)
    extraRules = [
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

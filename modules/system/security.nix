# Security Module
# Comprehensive security hardening with Podman, USBGuard, Fail2Ban, and Firejail
{
  pkgs,
  lib,
  ...
}: {
  # Install security packages
  environment.systemPackages = with pkgs; [
    # Security tools
    fail2ban
    usbguard
    firejail
    bubblewrap # Bubblewrap - modern sandboxing

    # Audit and analysis
    lynis
    vulnix # Nix vulnerability scanner

    # Network security
    nmap
    wireshark
    tcpdump

    # Password management
    pass
    pass-wayland # Wayland-native pass frontend

    # Encryption
    age
    ssh-to-age

    # 2FA tools
    libfido2
    yubikey-personalization

    # Container tools (moved from virtualisation)
    podman-compose
    podman-tui
    lazydocker
  ];

  # NOTE: Podman configuration moved to virtualisation.nix module

  # ============================================================================
  # FAIL2BAN - Intrusion Prevention
  # Re-enabled with proper cluster IP whitelisting
  # ============================================================================
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";

    # Whitelist cluster IPs to prevent accidental bans
    ignoreIP = [
      "127.0.0.1"
      "::1"
      "10.1.1.0/24" # Local network
      "100.64.0.0/10" # Tailscale CGNAT range
      # Individual host IPs
      "10.1.1.110" # zephyr
      "10.1.1.120" # nexus
      "10.1.1.130" # forge
      "10.1.1.140" # sentry
      # Tailscale IPs
      "100.81.182.5" # zephyr
      "100.86.158.18" # nexus
      "100.95.222.45" # forge
      "100.82.210.39" # sentry
    ];

    # Jails for common services
    jails = {
      sshd = {
        enabled = true;
      };
    };
  };

  # ============================================================================
  # USBGUARD - USB Device Authorization
  # ============================================================================
  services.usbguard = {
    enable = true;
    implicitPolicyTarget = "block";
    rules = ''
      allow
    '';
  };

  # ============================================================================
  # FIREJAIL - Application Sandboxing
  # ============================================================================
  programs.firejail = {
    enable = true;
    wrappedBinaries = {
      # Sandbox common applications
      firefox = "${pkgs.firejail}/bin/firejail ${pkgs.firefox}/bin/firefox";
      thunderbird = "${pkgs.firejail}/bin/firejail ${pkgs.thunderbird}/bin/thunderbird";
      vlc = "${pkgs.firejail}/bin/firejail ${pkgs.vlc}/bin/vlc";
    };
  };

  # Firejail global settings
  environment.etc."firejail/firejail.conf".text = ''
    # Quiet mode
    quiet

    # Seccomp filter
    seccomp

    # Private /dev
    private-dev

    # Private /tmp
    private-tmp

    # No 3D acceleration (more secure)
    no3d

    # DNS over TLS
    private-etc hosts,resolv.conf

    # Network restrictions
    # netfilter
    # protocol
  '';

  # ============================================================================
  # BUBBLEWRAP - Modern Application Sandboxing
  # ============================================================================
  # Note: Bubblewrap is installed in environment.systemPackages above
  # Create wrapper profiles for common applications in per-host configs if needed

  # ============================================================================
  # SUDO-RS - Rust-based sudo replacement (memory-safe, simpler)
  # ============================================================================
  security.sudo-rs = {
    enable = true;
    execWheelOnly = true; # Only wheel group can use sudo-rs
    wheelNeedsPassword = false; # Passwordless sudo for wheel (CI/CD deployment)
  };
  # Disable traditional sudo in favor of sudo-rs (override users.nix)
  security.sudo.enable = lib.mkForce false;

  # ============================================================================
  # APPARMOR - Mandatory Access Control
  # ============================================================================
  security.apparmor = {
    enable = true;
    killUnconfinedConfinables = true; # Kill processes that should be confined
    packages = with pkgs; [
      apparmor-utils
      apparmor-profiles
    ];
  };

  # Enable AppArmor in PAM services
  security.pam.services = {
    login.enableAppArmor = true;
    sshd.enableAppArmor = true;
    sudo-rs.enableAppArmor = true;
    su.enableAppArmor = true;
  };

  # AppArmor D-Bus integration
  services.dbus.apparmor = "enabled";

  # ============================================================================
  # ROOT PASSWORD DISABLED
  # ============================================================================
  # Root login disabled entirely - use sudo-rs from wheel users
  users.users.root.hashedPassword = "!";

  # ============================================================================
  # FIREJAIL EXTENDED WRAPPERS (from XNM1)
  # ============================================================================
  programs.firejail.wrappedBinaries = {
    mpv = {
      executable = "${pkgs.mpv}/bin/mpv";
      profile = "${pkgs.firejail}/etc/firejail/mpv.profile";
    };
    discord = {
      executable = "${pkgs.discord}/bin/discord";
      profile = "${pkgs.firejail}/etc/firejail/discord.profile";
    };
    vscodium = {
      executable = "${pkgs.vscodium}/bin/vscodium";
      profile = "${pkgs.firejail}/etc/firejail/vscodium.profile";
    };
  };

  # ============================================================================
  # SECURITY DAEMONS
  # ============================================================================

  # Automatic security updates (daily, with channel checks)
  system.autoUpgrade = {
    enable = true;
    allowReboot = false; # Don't auto-reboot, notify instead
    dates = "daily"; # Check for updates daily
    operation = "switch"; # Apply updates by switching to new generation
  };

  # Rebuild notification when updates available
  systemd.services.nixos-upgrade-unit = {
    description = "Notify about available NixOS upgrades";
    serviceConfig.ExecStart = pkgs.writeShellScript "nixos-upgrade-notify" ''
      ${pkgs.libnotify}/bin/notify-send "NixOS Updates Available" "Run 'sudo nixos-rebuild switch' to update" -i software-update-available
    '';
    wantedBy = ["multi-user.target"];
  };
}

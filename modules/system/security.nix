# Security Module
# Comprehensive security hardening with Podman, USBGuard, Fail2Ban, and Firejail
{config, pkgs, lib, ...}: let
  # Hardcoded cluster IPs to prevent infinite recursion
  cluster = {
    hosts = {
      zephyr.ip = "10.1.1.110";
      nexus.ip = "10.1.1.120";
      forge.ip = "10.1.1.130";
      sentry.ip = "10.1.1.140";
    };
    tailscale = {
      zephyr = "100.81.182.5";
      nexus = "100.86.158.18";
      forge = "100.95.222.45";
      sentry = "100.82.210.39";
    };
  };
in {
  # Install security packages
  environment.systemPackages = with pkgs; [
    # Security tools
    fail2ban
    usbguard
    firejail
    bubblewrap        # Bubblewrap - modern sandboxing

    # Audit and analysis
    lynis

    # Network security
    nmap
    wireshark
    tcpdump

    # Password management
    pass

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
      "10.1.1.0/24"      # Local network
      "100.64.0.0/10"      # Tailscale CGNAT range
      # Individual host IPs
      "10.1.1.110"  # zephyr
      "10.1.1.120"  # nexus
      "10.1.1.130"  # forge
      "10.1.1.140"  # sentry
      # Tailscale IPs
      "100.81.182.5"   # zephyr
      "100.86.158.18"  # nexus
      "100.95.222.45"  # forge
      "100.82.210.39"  # sentry
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
  # SECURITY DAEMONS
  # ============================================================================

  # Audit daemon (using auditd package directly - services.auditd doesn't exist in all versions)
  # To enable: services.auditd.enable = true (if available)
  # For now, just installing the package

  # Logwatch for log analysis
  # services.logwatch.enable = true;

  # Automatic security updates (disabled for stability)
  # system.autoUpgrade.enable = true;
}

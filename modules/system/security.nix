# Security Module
# Comprehensive security hardening with Podman, USBGuard, Fail2Ban, and Firejail
{
  config,
  pkgs,
  lib,
  ...
}: let
  # Use centralized network constants to avoid duplication
  clusterHosts = config.networking.cluster.hosts;
  clusterSubnet = config.networking.cluster.subnet;
  tailscaleCgnat = "100.64.0.0/10";
in {
  # Install security packages
  environment.systemPackages = with pkgs; [
    # Security tools
    fail2ban
    usbguard
    firejail
    bubblewrap # Bubblewrap - modern sandboxing

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
    # Uses network-constants to avoid duplication
    ignoreIP = [
      "127.0.0.1"
      "::1"
      clusterSubnet
      tailscaleCgnat
      # Individual host IPs from network-constants
      clusterHosts.zephyr.ip
      clusterHosts.nexus.ip
      clusterHosts.forge.ip
      clusterHosts.sentry.ip
      # Tailscale IPs
      clusterHosts.zephyr.tailscale
      clusterHosts.nexus.tailscale
      clusterHosts.forge.tailscale
      clusterHosts.sentry.tailscale
    ];

    # Jails for common services
    jails = {
      sshd = {
        enabled = true;
      };

      # Mining API protection - rate limit localhost access
      # Prevents potential abuse even though APIs are localhost-only
      xmrig-api = {
        enabled = true;
        filter = "xmrig-api";
        settings = {
          logpath = "/var/log/mining/*.log";
          maxretry = 10;
          findtime = "1h";
          bantime = "24h";
          port = "8081";
          protocol = "tcp";
        };
      };

      lolminer-api = {
        enabled = true;
        filter = "lolminer-api";
        settings = {
          logpath = "/var/log/mining/*.log";
          maxretry = 10;
          findtime = "1h";
          bantime = "24h";
          port = "4068,4069";
          protocol = "tcp";
        };
      };
    };
  };

  # Custom fail2ban filters for mining APIs
  environment.etc."fail2ban/filter.d/xmrig-api.conf".text = ''
    [Definition]
    # Block IPs making excessive API requests to XMRig
    failregex = ^.*\sWARNING\s.*\sclient\s<HOST>\s.*$
    ignoreregex =
  '';

  environment.etc."fail2ban/filter.d/lolminer-api.conf".text = ''
    [Definition]
    # Block IPs making excessive API requests to lolMiner
    failregex = ^.*API\sconnection\sfrom\s<HOST>.*$
    ignoreregex =
  '';

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

  # ============================================================================
  # KERNEL HARDENING - Disable Core Dumps
  # ============================================================================
  # Prevent core dumps from being written to disk (security risk)
  boot.kernelParams = ["coredump=disable"];
  # Also disable via sysctl as additional protection
  boot.kernel.sysctl."kernel.core_pattern" = "|/bin/false";
  boot.kernel.sysctl."fs.suid_dumpable" = 0;
}

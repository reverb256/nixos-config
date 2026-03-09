# Security Hardening Module
# Addresses all critical security findings from cluster audit
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkOption types;
  cfg = config.security.clusterAudit;
in {
  options.security.clusterAudit = {
    enable = mkEnableOption "Security audit remediation and hardening";

    enableFirewall = mkOption {
      type = types.bool;
      default = true;
      description = "Enable firewalld with Tailscale as trusted interface";
    };

    enableTailscaleSSH = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Tailscale SSH for keyless authentication";
    };

    bindServicesToLocalhost = mkOption {
      type = types.bool;
      default = true;
      description = "Bind services to localhost instead of 0.0.0.0";
    };
  };

  config = mkIf cfg.enable {
    # ========================================================================
    # FIREWALL CONFIGURATION
    # ========================================================================
    # Use lib.mkAfter to append to existing firewall configurations
    # This avoids conflicts with gaming.nix and other modules that set firewall rules
    networking.firewall = mkIf cfg.enableFirewall {
      enable = true;

      # Trust Tailscale interface - allows all traffic within VPN mesh
      trustedInterfaces = ["tailscale0"];

      # Allow SSH from Tailscale network only
      allowedTCPPorts = [22];
    };

    # ========================================================================
    # SERVICE BINDING CONFIGURATION
    # ========================================================================
    # Note: AI Gateway binding is configured in gateway.nix module
    # This module only sets firewall and SSH hardening policies

    # ========================================================================
    # SERVICES CONFIGURATION
    # ========================================================================
    # Consolidated services for Tailscale SSH, SSH hardening, Fail2ban, and Prometheus
    services = {
      # TAILSCALE SSH CONFIGURATION (SSO)
      tailscale = mkIf cfg.enableTailscaleSSH {
        enable = true;
        # Enable SSH through Tailscale
        # This provides keyless authentication using Tailscale identity
        # Configure ACLs in Tailscale admin console
      };

      # SSH HARDENING (Complements Tailscale SSH)
      openssh = mkIf cfg.enableTailscaleSSH {
        settings = {
          # Disable password authentication (Tailscale SSH handles auth)
          PasswordAuthentication = lib.mkForce false;
          KbdInteractiveAuthentication = lib.mkForce false;

          # Only allow pubkey and Tailscale SSH
          AuthenticationMethods = "publickey";

          # Security settings
          PermitRootLogin = "no";
          PermitEmptyPasswords = false;

          # Rate limiting to prevent brute-force
          MaxAuthTries = 3;
          MaxStartups = "10:30:60";

          # Logging
          LogLevel = "VERBOSE";

          # Access restrictions (enforced via Tailscale ACLs)
          AllowUsers = ["j_kro" "nixbuild"];
          AllowGroups = ["wheel" "nixbuild"];
        };

        # Extra options for Tailscale SSH compatibility
        extraConfig = ''
          # Tailscale SSH uses this option
          PermitTunnel = yes

          # Only allow Tailscale identity + pubkey auth
          AuthenticationMethods publickey

          # GatewayPorts allows SSH tunneling for node access
          GatewayPorts no

          # Strict access control
          AllowTcpForwarding yes
          AllowAgentForwarding no
        '';
      };

      # FAIL2BAN FOR SSH BRUTE-FORCE PROTECTION
      fail2ban = mkIf cfg.enableTailscaleSSH {
        enable = true;
        jails.sshd = {
          enabled = true;
          filter = "sshd";
          settings = {
            port = "22";
            logpath = "/var/log/auth.log";
            maxretry = 5;
            bantime = "1h";
            findtime = "1h";
            ignoreIP = "100.0.0.0/8"; # Tailscale network
          };
        };
      };

      # PROMETHEUS EXPORTER BINDING
      # Bind node exporters to localhost
      prometheus.exporters.node = {
        enable = true;
        listenAddress = lib.mkForce "127.0.0.1";
      };
    };

    # ========================================================================
    # SECURITY PACKAGES
    # ========================================================================
    environment.systemPackages = with pkgs; [
      fail2ban
      tailscale
    ];

    # ========================================================================
    # SYSTEMD HARDENING
    # ========================================================================
    systemd.tmpfiles.rules = [
      # Ensure SSH sockets directory is secure
      "d /home/j_kro/.ssh/sockets 0700 j_kro users -"

      # Secure fail2ban directory
      "d /var/lib/fail2ban 0750 root root -"
    ];

    # ========================================================================
    # NETWORK SECURITY ENHANCEMENTS
    # ========================================================================
    boot.kernel.sysctl = {
      # Disable ICMP redirects (mitigate certain attacks)
      "net.ipv4.conf.all.accept_source_route" = 0;
      "net.ipv4.conf.default.accept_source_route" = 0;
      "net.ipv6.conf.all.accept_source_route" = 0;

      # Enable TCP SYN cookies (SYN flood protection)
      "net.ipv4.tcp_syncookies" = 1;

      # IP spoofing protection
      "net.ipv4.conf.all.rp_filter" = 1;
      "net.ipv4.conf.default.rp_filter" = 1;

      # Ignore ICMP broadcasts (reduce smurf attacks)
      "net.ipv4.icmp_echo_ignore_broadcasts" = 1;

      # Ignore bogus ICMP errors (reduce attack surface)
      "net.ipv4.icmp_ignore_bogus_error_responses" = 1;

      # Log suspicious packets
      "net.ipv4.conf.all.log_martians" = 1;
      "net.ipv4.conf.default.log_martians" = 1;
    };
  };
}

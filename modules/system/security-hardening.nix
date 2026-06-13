{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
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
    # FIDO2/U2F for console login and sudo
    security.pam.u2f = {
      enable = true;
      settings = {
        cue = true;
        authfile = "/home/j_kro/.config/Yubico/u2f_keys";
      };
    };

    networking.firewall = mkIf cfg.enableFirewall {
      enable = lib.mkDefault true;

      trustedInterfaces = ["tailscale0"];

      allowedTCPPorts = lib.mkOptionDefault [];
    };

    services = {
      tailscale = mkIf cfg.enableTailscaleSSH {
        enable = lib.mkDefault true;
      };

      openssh = mkIf cfg.enableTailscaleSSH {
        settings = {
          PasswordAuthentication = lib.mkForce false;
          KbdInteractiveAuthentication = lib.mkForce false;

          AuthenticationMethods = "publickey";

          PermitRootLogin = "no";
          PermitEmptyPasswords = false;

          MaxAuthTries = 3;
          MaxStartups = "10:30:60";

          LogLevel = "VERBOSE";

          AllowUsers = [
            "j_kro"
            "nixbuild"
          ];
          AllowGroups = [
            "wheel"
            "nixbuild"
          ];
        };

        extraConfig = ''
          PermitTunnel = yes

          AuthenticationMethods publickey

          GatewayPorts no

          AllowTcpForwarding yes
          AllowAgentForwarding no
        '';
      };

      fail2ban = mkIf cfg.enableTailscaleSSH {
        enable = lib.mkDefault true;
        jails.sshd = {
          enabled = true;
          filter = "sshd";
          settings = {
            port = "22";
            backend = "systemd";
            maxretry = 5;
            bantime = "1h";
            findtime = "1h";
            ignoreIP = "100.0.0.0/8 10.1.1.0/24 127.0.0.0/8";
          };
        };
      };

      prometheus.exporters.node = {
        enable = lib.mkDefault true;
        listenAddress = lib.mkDefault "127.0.0.1";
      };
    };

    environment.systemPackages = with pkgs; [
      fail2ban
      tailscale
    ];

    systemd.tmpfiles.rules = [
      "d /home/j_kro/.ssh/sockets 0700 j_kro users -"

      "d /var/lib/fail2ban 0750 root root -"
    ];

    boot.kernel.sysctl = {
      "net.ipv4.conf.all.accept_source_route" = 0;
      "net.ipv4.conf.default.accept_source_route" = 0;
      "net.ipv6.conf.all.accept_source_route" = 0;

      "net.ipv4.tcp_syncookies" = 1;

      "net.ipv4.conf.all.rp_filter" = lib.mkDefault 1;
      "net.ipv4.conf.default.rp_filter" = lib.mkDefault 1;

      "net.ipv4.icmp_echo_ignore_broadcasts" = 1;

      "net.ipv4.icmp_ignore_bogus_error_responses" = 1;

      "net.ipv4.conf.all.log_martians" = 1;
      "net.ipv4.conf.default.log_martians" = 1;
    };
  };
}

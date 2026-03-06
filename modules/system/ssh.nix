# Common SSH Configuration
# Uses network-constants.nix for host IPs
{config, pkgs, ...}: let
  # Hardcoded cluster IPs to prevent infinite recursion
  hosts = {
    nexus = {
      ip = "10.1.1.120";
      tailscale = "100.86.158.18";
    };
    forge = {
      ip = "10.1.1.130";
      tailscale = "100.95.222.45";
    };
    sentry = {
      ip = "10.1.1.140";
      tailscale = "100.82.210.39";
    };
  };
in {
  services.openssh = {
    enable = true;
    settings = {
      # Authentication Settings - Password auth enabled for j_kro
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = true;
      PubkeyAuthentication = true;
      PermitRootLogin = "no";
      PermitEmptyPasswords = false;
      ChallengeResponseAuthentication = false;

      # Modern Cryptographic Settings (Mozilla Modern recommendations)
      Ciphers = [
        "chacha20-poly1305@openssh.com"
        "aes256-gcm@openssh.com"
        "aes128-gcm@openssh.com"
        "aes256-ctr"
        "aes192-ctr"
        "aes128-ctr"
      ];

      KexAlgorithms = [
        "mlkem768x25519-sha256"
        "curve25519-sha256"
        "curve25519-sha256@libssh.org"
        "diffie-hellman-group-exchange-sha256"
      ];

      Macs = [
        "hmac-sha2-512-etm@openssh.com"
        "hmac-sha2-256-etm@openssh.com"
        "umac-128-etm@openssh.com"
      ];

      # Security and Performance Settings
      UseDns = false;
      LogLevel = "VERBOSE";
      AllowUsers = ["j_kro" "nixbuild"];
      AllowGroups = ["wheel" "nixbuild"];
      ClientAliveInterval = 300;
      ClientAliveCountMax = 0;
      MaxAuthTries = 3;
      MaxSessions = 10;

      # TCP forwarding needed for node tunnels via Tailscale
      AllowTcpForwarding = true;

      # Disable other features we don't use
      AllowAgentForwarding = false;
      X11Forwarding = false;
    };
  };

  # Declarative known hosts for cluster hosts
  # Uses network constants instead of hardcoded IPs
  programs.ssh.knownHosts = {
    nexus = {
      hostNames = ["nexus" hosts.nexus.ip hosts.nexus.tailscale];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEldBvJIZYJKHw8pt0/Bx3xhJK4rSrhno0NyHgTtWAaV";
    };
    forge = {
      hostNames = ["forge" hosts.forge.ip hosts.forge.tailscale];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINhHtW56M3KuMH/qCwamdGKQe22NuemFQaYV7LhJXdUz";
    };
    sentry = {
      hostNames = ["sentry" hosts.sentry.ip hosts.sentry.tailscale];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBK7IznKNG8BJVrPv1dnJBrbFhcmzTKaYSAzVdrXV7Fn";
    };
  };

  # SSH client configuration for cluster access
  # Uses network constants for IPs
  environment.etc."ssh/config" = {
    source = pkgs.writeText "ssh-config" ''
      # SSH client configuration for cluster access
      ControlMaster auto
      ControlPersist 600
      ServerAliveInterval 60
      ServerAliveCountMax 3
      Compression yes
      TCPKeepAlive yes
      UserKnownHostsFile ~/.ssh/known_hosts

      # Default settings for all hosts (j_kro user for manual access)
      Host *
        User j_kro
        IdentityFile ~/.ssh/id_ed25519
        IdentitiesOnly yes
        StrictHostKeyChecking accept-new
        ConnectTimeout 5

      # Build machines - use j_kro user for distributed builds
      # Support both local IP and Tailscale IP for mosh compatibility
      Host nexus ${hosts.nexus.ip} ${hosts.nexus.tailscale}
        HostName ${hosts.nexus.tailscale}
        User j_kro
        IdentityFile /home/j_kro/.ssh/id_nixbuild
        ControlPath ~/.ssh/sockets/ssh-%r@%h:%p

      Host forge ${hosts.forge.ip} ${hosts.forge.tailscale}
        HostName ${hosts.forge.tailscale}
        User j_kro
        IdentityFile /home/j_kro/.ssh/id_nixbuild
        ControlPath ~/.ssh/sockets/ssh-%r@%h:%p

      Host sentry ${hosts.sentry.ip} ${hosts.sentry.tailscale}
        HostName ${hosts.sentry.tailscale}
        User j_kro
        IdentityFile /home/j_kro/.ssh/id_nixbuild
        ControlPath ~/.ssh/sockets/ssh-%r@%h:%p

      # GitHub - for CI/CD deploys
      Host github.com
        HostName github.com
        User git
        IdentityFile ~/.ssh/id_deploy
        IdentitiesOnly yes
    '';
  };

  # SSH agent is enabled via programs.ssh.startAgent in distributed-builds.nix

  # SSH keys are defined in modules/users.nix
  # This prevents duplicate definition conflicts

  # Ensure SSH sockets directory exists with proper permissions
  systemd.tmpfiles.rules = [
    "d /home/j_kro/.ssh/sockets 0700 j_kro users -"
  ];
}

# Common SSH Configuration
{pkgs, ...}: {
  services.openssh = {
    enable = true;
    settings = {
      # Authentication Settings - Security hardened
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
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

      # TCP forwarding needed for OpenClaw node tunnels via Tailscale
      AllowTcpForwarding = true;

      # Disable other features we don't use
      AllowAgentForwarding = false;
      X11Forwarding = false;
    };
  };

  # SSH client configuration for cluster access
  # Note: Build machine configs are in distributed-builds.nix
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

      # Build machines - use nixbuild user (configured in distributed-builds.nix)
      # These override the default user for distributed builds
      Host nexus 10.1.1.120
        HostName 10.1.1.120
        User nixbuild
        IdentityFile /home/j_kro/.ssh/id_nixbuild
        ControlPath ~/.ssh/sockets/ssh-%r@%h:%p

      Host forge 10.1.1.130
        HostName 10.1.1.130
        User nixbuild
        IdentityFile /home/j_kro/.ssh/id_nixbuild
        ControlPath ~/.ssh/sockets/ssh-%r@%h:%p

      Host sentry 10.1.1.140
        HostName 10.1.1.140
        User nixbuild
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
  # Note: Using 'users' group instead of 'j_kro' group since the user belongs to 'users' group (gid=100)
  systemd.tmpfiles.rules = [
    "d /home/j_kro/.ssh/sockets 0700 j_kro users -"
  ];
}

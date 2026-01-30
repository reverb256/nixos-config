# Common SSH Configuration
{pkgs, ...}: {
  services.openssh = {
    enable = true;
    settings = {
      # Authentication Settings - Allow password auth for j_kro and root
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = true;
      PubkeyAuthentication = true;
      PermitRootLogin = "no";

      # Modern Cryptographic Settings
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
        "sntrup761x25519-sha512"
        "sntrup761x25519-sha512@openssh.com"
        "curve25519-sha256"
        "curve25519-sha256@libssh.org"
        "diffie-hellman-group-exchange-sha256"
      ];

      Macs = [
        "hmac-sha2-512-etm@openssh.com"
        "hmac-sha2-256-etm@openssh.com"
        "umac-128-etm@openssh.com"
      ];

      # Performance Settings
      UseDns = false;
      LogLevel = "INFO";
    };
  };

  # SSH client configuration for cluster access - create config file
  environment.etc."ssh/config" = {
    source = pkgs.writeText "ssh-config" ''
      # SSH client configuration for cluster access
      ControlMaster auto
      ControlPersist 600
      ServerAliveInterval 60
      ServerAliveCountMax 3

      # Nexus - Build node
      Host nexus
        HostName 10.1.1.120
        User j_kro
        IdentityFile ~/.ssh/id_rsa
        StrictHostKeyChecking no
        UserKnownHostsFile /dev/null
        ControlMaster auto
        ControlPath ~/.ssh/sockets/ssh-%r@%h:%p
        ControlPersist 600

      # Forge - Build/Development node
      Host forge
        HostName 10.1.1.130
        User j_kro
        IdentityFile ~/.ssh/id_rsa
        StrictHostKeyChecking no
        UserKnownHostsFile /dev/null
        ControlMaster auto
        ControlPath ~/.ssh/sockets/ssh-%r@%h:%p
        ControlPersist 600

      # Sentry - Monitoring node
      Host sentry
        HostName 10.1.1.140
        User j_kro
        IdentityFile ~/.ssh/id_rsa
        StrictHostKeyChecking no
        UserKnownHostsFile /dev/null
        ControlMaster auto
        ControlPath ~/.ssh/sockets/ssh-%r@%h:%p
        ControlPersist 600

      # Cluster wildcard
      Host zephyr nexus forge sentry
        User j_kro
        IdentityFile ~/.ssh/id_rsa
        StrictHostKeyChecking no
        UserKnownHostsFile /dev/null
        ControlMaster auto
        ControlPath ~/.ssh/sockets/ssh-%r@%h:%p
        ControlPersist 600
    '';
  };

  # SSH keys are defined in modules/users.nix
  # This prevents duplicate definition conflicts

  # Ensure SSH sockets directory exists with proper permissions for user
  systemd.tmpfiles.rules = [
    "d /home/j_kro/.ssh/sockets 0700 j_kro j_kro -"
  ];
}

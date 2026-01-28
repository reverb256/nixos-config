# Common SSH Configuration
{pkgs, ...}: {
  services.openssh = {
    enable = true;
    settings = {
      # Authentication Settings - Allow password auth for j_kro and root
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = true;
      PubkeyAuthentication = true;
      PermitRootLogin = "yes";

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
        ControlPath /tmp/ssh-%h-%p
        ControlPersist 600

      # Forge - Build/Development node
      Host forge
        HostName 10.1.1.130
        User j_kro
        IdentityFile ~/.ssh/id_rsa
        StrictHostKeyChecking no
        UserKnownHostsFile /dev/null
        ControlMaster auto
        ControlPath /tmp/ssh-%h-%p
        ControlPersist 600

      # Sentry - Monitoring node
      Host sentry
        HostName 10.1.1.140
        User j_kro
        IdentityFile ~/.ssh/id_rsa
        StrictHostKeyChecking no
        UserKnownHostsFile /dev/null
        ControlMaster auto
        ControlPath /tmp/ssh-%h-%p
        ControlPersist 600

      # Cluster wildcard
      Host zephyr nexus forge sentry
        User j_kro
        IdentityFile ~/.ssh/id_rsa
        StrictHostKeyChecking no
        UserKnownHostsFile /dev/null
        ControlMaster auto
        ControlPath /tmp/ssh-%h-%p
        ControlPersist 600
    '';
  };

  # Add SSH key to authorized_keys for j_kro user
  users.users.j_kro.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCUwUcRSasufZT4RoqzX/S15AVlXqk9ebf5npfy4ws9I8phm05v4Bh4udXVRP2679sISQM5HABvPazoFeK5/QvrE8Daz7jqufGvwZvuP+qXg3hNBd3b0c80P5HoNIOn8d3eUd5eKbZzU+23dc4GiowzyDM+5bMwiSNkwFNzf5a9tj1FHSSRKKlc7fltei9sgmLNMzGYdHQQOr/yVGPFFk6/Tb+Gz7ZNZ9AP7pi3eFkiYc+g8wujSUtl7jTvvzcXl7+f4tf+NphBQ1Db68e3R1e+e0iTEqUnbjedjUdOnVK/nkURXABOV9kNOuISuQ9e+5q8w8FHWgNaSJYeAyYNZLVG6hEJo/ptA8zBe4jUnKvFZ9avRjZvKXDQJTOeOH46Gz1mUlPx/6jEwgCOyNIu8/Udunk0XHIXhIDEhXl0KA6OUPs8Od8+KuZx+IuTyov+bSe68GYjwadPcNNDPFZrs8nJlqfYLA0epg0pHLl2K/FspQohGhQNHn9qwiNx94ljMKkQRz1jD1klk2m5WRHy4Mr8WNwFm266W23/Xc8OomF2zoUV+VcqtZX2kG4NB6QSOacERXq9FFS3/UXqZ29BA+k2RDuddjeYmgRX5wi+VznHvuCNpR0FuoZPYw95N0ZnOEimxB+L1IPDMn6rUCh76phroqgY+M0yt27M8XV8qsZFJw== j_kro@zephyr"
  ];
}

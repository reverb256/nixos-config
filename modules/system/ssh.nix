{pkgs, lib, ...}: let
  inherit (lib) mkOptionDefault;

  hosts = {
    zephyr = {
      ip = "10.1.1.110";
      tailscale = "100.81.182.5";
    };
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
    krash3 = {
      ip = "10.1.1.150";
      tailscale = null;
    };
  };

  # All mesh SSH keys for round-trip distributed builds
  meshKeys = import ../../mesh-keys.nix;
in {
  services.openssh = {
    settings.HostCertificate = "/etc/ssh/ssh_host_ed25519_key-cert.pub";
    enable = true;
    settings = {
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = true;
      PubkeyAuthentication = true;
      PermitRootLogin = "no";
      PermitEmptyPasswords = false;
      ChallengeResponseAuthentication = true;

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

      UseDns = false;
      LogLevel = "VERBOSE";
      AllowUsers = [
        "j_kro"
        "nixbuild"
        "cluster-mesh"
      ];
      AllowGroups = [
        "wheel"
        "nixbuild"
      ];
      ClientAliveInterval = 300;
      ClientAliveCountMax = 0;
      MaxAuthTries = 3;
      MaxSessions = 10;

      AllowTcpForwarding = true;

      AllowAgentForwarding = false;
      X11Forwarding = false;
    };
  };

  # SSH CA known hosts — populated by modules/security/ssh-ca.nix via services.openssh.knownHosts

  users.users.j_kro.openssh.authorizedKeys.keys = meshKeys;

  programs.ssh.extraConfig = ''
    ControlMaster auto
    ControlPersist 600
    ServerAliveInterval 60
    ServerAliveCountMax 3
    Compression yes
    TCPKeepAlive yes
    UserKnownHostsFile ~/.ssh/known_hosts

    Host *
      User j_kro
      IdentityFile ~/.ssh/id_ed25519
      IdentitiesOnly yes
      StrictHostKeyChecking yes
      ConnectTimeout 5

    Host zephyr ${hosts.zephyr.ip}
      HostName ${hosts.zephyr.ip}
      User j_kro
      IdentityFile ~/.ssh/id_ed25519
      ControlPath ~/.ssh/sockets/ssh-%r@%h:%p

    Host nexus ${hosts.nexus.ip}
      HostName ${hosts.nexus.ip}
      User j_kro
      IdentityFile ~/.ssh/id_ed25519
      ControlPath ~/.ssh/sockets/ssh-%r@%h:%p

    Host forge ${hosts.forge.ip}
      HostName ${hosts.forge.ip}
      User j_kro
      IdentityFile ~/.ssh/id_ed25519
      ControlPath ~/.ssh/sockets/ssh-%r@%h:%p

    Host sentry ${hosts.sentry.ip}
      HostName ${hosts.sentry.ip}
      User j_kro
      IdentityFile ~/.ssh/id_ed25519
      ControlPath ~/.ssh/sockets/ssh-%r@%h:%p

    Host krash3 ${hosts.krash3.ip}
      HostName ${hosts.krash3.ip}
      Port 22
      User j_kro
      StrictHostKeyChecking accept-new
      IdentityFile ~/.ssh/id_ed25519
      ControlPath ~/.ssh/sockets/ssh-%r@%h:%p

    Host krash3-wsl
      HostName 10.1.1.90
      Port 22222
      User j_kro
      StrictHostKeyChecking accept-new
      IdentityFile ~/.ssh/id_ed25519

    Host github.com
      HostName github.com
      User git
      IdentityFile ~/.ssh/id_deploy
      IdentitiesOnly yes
  '';

  # System-level SSH config for distributed build machines (used by nix-daemon)
  environment.etc."ssh/ssh_config.d/50-build-machines.conf".text = ''
    Host zephyr nexus sentry
      User j_kro
      IdentityFile /etc/nixos/ssh/id_ed25519
      IdentitiesOnly yes
      StrictHostKeyChecking accept-new
      ConnectTimeout 30
  '';

  systemd.tmpfiles.rules = [
    "d /home/j_kro/.ssh/sockets 0700 j_kro users -"
  ];

  networking.firewall.interfaces = {
    tailscale0.allowedTCPPorts = [22];
  };
  networking.firewall.extraInputRules = ''
    ip saddr 10.1.1.0/24 tcp dport 22 accept
    iifname "lo" tcp dport 22 accept
  '';
}

{ pkgs, ... }:
let
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
  };

  j_kroPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEvekxGk1YR/eF8llVmNk3C59BtgB+9DNvxLy2WjPEyb j_kro@zephyr";
in
{
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PubkeyAuthentication = true;
      PermitRootLogin = "no";
      PermitEmptyPasswords = false;
      ChallengeResponseAuthentication = false;

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

  programs.ssh.knownHosts = {
    zephyr = {
      hostNames = [
        "zephyr"
        hosts.zephyr.ip
        hosts.zephyr.tailscale
      ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA0/pTXa/H7mvy3+YPJq9U2mFKO4+YrLSOYd8sPU44+q";
    };
    nexus = {
      hostNames = [
        "nexus"
        hosts.nexus.ip
        hosts.nexus.tailscale
      ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEldBvJIZYJKHw8pt0/Bx3xhJK4rSrhno0NyHgTtWAaV";
    };
    forge = {
      hostNames = [
        "forge"
        hosts.forge.ip
        hosts.forge.tailscale
      ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINhHtW56M3KuMH/qCwamdGKQe22NuemFQaYV7LhJXdUz";
    };
    sentry = {
      hostNames = [
        "sentry"
        hosts.sentry.ip
        hosts.sentry.tailscale
      ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBK7IznKNG8BJVrPv1dnJBrbFhcmzTKaYSAzVdrXV7Fn";
    };
  };

  users.users.j_kro.openssh.authorizedKeys.keys = [ j_kroPublicKey ];

  environment.etc."ssh/config" = {
    source = pkgs.writeText "ssh-config" ''
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

      Host zephyr ${hosts.zephyr.ip} ${hosts.zephyr.tailscale}
        HostName ${hosts.zephyr.tailscale}
        User j_kro
        IdentityFile ~/.ssh/id_ed25519
        ControlPath ~/.ssh/sockets/ssh-%r@%h:%p

      Host nexus ${hosts.nexus.ip} ${hosts.nexus.tailscale}
        HostName ${hosts.nexus.tailscale}
        User j_kro
        IdentityFile ~/.ssh/id_ed25519
        ControlPath ~/.ssh/sockets/ssh-%r@%h:%p

      Host forge ${hosts.forge.ip} ${hosts.forge.tailscale}
        HostName ${hosts.forge.tailscale}
        User j_kro
        IdentityFile ~/.ssh/id_ed25519
        ControlPath ~/.ssh/sockets/ssh-%r@%h:%p

      Host sentry ${hosts.sentry.ip} ${hosts.sentry.tailscale}
        HostName ${hosts.sentry.tailscale}
        User j_kro
        IdentityFile ~/.ssh/id_ed25519
        ControlPath ~/.ssh/sockets/ssh-%r@%h:%p

      Host github.com
        HostName github.com
        User git
        IdentityFile ~/.ssh/id_deploy
        IdentitiesOnly yes
    '';
  };



  systemd.tmpfiles.rules = [
    "d /home/j_kro/.ssh/sockets 0700 j_kro users -"
  ];

  networking.firewall.interfaces = {
    tailscale0.allowedTCPPorts = [ 22 ];
  };
  networking.firewall.extraInputRules = ''
    ip saddr 10.1.1.0/24 tcp dport 22 accept
    iifname "lo" tcp dport 22 accept
  '';
}

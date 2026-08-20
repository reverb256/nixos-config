{
  config,
  lib,
  pkgs,
  ...
}: let
  # #309: derive from the declared user instead of hardcoding /home/j_kro.
  userHome = config.users.users.j_kro.home or "/home/j_kro";
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
    krash2 = {
      ip = "10.1.1.79";
      tailscale = null;
    };
  };

  # All mesh SSH keys for round-trip distributed builds
  meshKeys = import ../../mesh-keys.nix;
in {
  services.openssh = {
    enable = lib.mkDefault true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PubkeyAuthentication = true;
      PermitRootLogin = lib.mkDefault "no";
      PermitEmptyPasswords = false;
      ChallengeResponseAuthentication = false;

      # CA trust is centralized in modules/system/ssh-ca.nix (legacy module,
      # enabled by default; TrustedUserCAKeys lists cluster-CA@zephyr + YubiKey
      # ECDSA + clusterCaPublicKey). Do NOT add another TrustedUserCAKeys here —
      # OpenSSH merges multiple lines but warns on duplicates.

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

  programs.ssh.knownHosts = {
    # @cert-authority: trust ANY host key signed by the canonical cluster SSH
    # CA (live /etc/ssh/ca_key on zephyr, G3m+DW7Y...). Combined with the
    # declarative ssh-host-cert-sign service, host-key rotation (e.g. after a
    # reinstall) no longer triggers MITM warnings — the fresh key is re-signed
    # on boot and accepted via this CA entry. NixOS joins hostNames with commas
    # into a single known_hosts line, so the marker + all patterns must live in
    # ONE element (wildcards cover .lan + .cluster.local; IPs/tailscale pinned
    # individually below for the exact-address paths).
    cert-authority = {
      hostNames = ["@cert-authority *.lan,*.cluster.local,10.1.1.110,10.1.1.120,10.1.1.130,10.1.1.140,100.81.182.5,100.86.158.18,100.95.222.45,100.82.210.39"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIINREWq2TwFSGaDxTBDv7xaFGw7fniE10i91sn6Xqhkg cluster-CA@zephyr";
    };
    # Cluster host keys are NOT pinned below. The @cert-authority entry above
    # (cert-authority = { ... }) trusts ANY host key signed by cluster-CA@zephyr,
    # and the declarative ssh-host-cert-sign service re-signs each host's cert
    # on boot (principals cover hostname + .lan + IP + tailscale). Pinning raw
    # host keys here is the recurring root cause of 'REMOTE HOST IDENTIFICATION
    # HAS CHANGED' after a disko reinstall / key rotation: the stale pin conflicts
    # with the CA-validated cert and breaks SSH from every host that cached the
    # old pin (observed 2026-08-19: forge broke from sentry + self after a cert
    # re-sign). Removing the pins makes rotation frictionless -- the CA is the
    # sole trust path. github.com below is a public CA-trusted key, kept.
    github = {
      hostNames = ["github.com"];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
    };
  };

  users.users.j_kro.openssh.authorizedKeys.keys = meshKeys;

  programs.ssh.extraConfig = ''
    ControlMaster auto
    ControlPersist 600
    ServerAliveInterval 60
    ServerAliveCountMax 3
    Compression yes
    TCPKeepAlive yes
    UserKnownHostsFile ~/.ssh/known_hosts /etc/ssh/ssh_known_hosts

    Host *
      User j_kro
      IdentityFile ~/.ssh/id_ed25519
      IdentitiesOnly yes
      StrictHostKeyChecking yes
      ConnectTimeout 5

    Host zephyr ${hosts.zephyr.ip} ${hosts.zephyr.tailscale}
      HostName ${hosts.zephyr.ip}
      User j_kro
      IdentityFile ~/.ssh/id_ed25519
      ControlPath ~/.ssh/sockets/ssh-%r@%h:%p

    # Cluster build-farm / mesh hosts use the touchless cluster key
    # (id_ed25519_cluster) so agentic/non-interactive SSH never prompts for
    # the YubiKey SK touch. Restored after the Home Manager extraction dropped
    # this block (live config had it; source did not).
    Host nexus ${hosts.nexus.ip} ${hosts.nexus.tailscale}
      HostName ${hosts.nexus.ip}
      User j_kro
      IdentityFile ~/.ssh/id_ed25519_cluster
      IdentitiesOnly yes
      ControlPath ~/.ssh/sockets/ssh-%r@%h:%p

    Host forge ${hosts.forge.ip} ${hosts.forge.tailscale}
      HostName ${hosts.forge.ip}
      User j_kro
      IdentityFile ~/.ssh/id_ed25519_cluster
      IdentitiesOnly yes
      ControlPath ~/.ssh/sockets/ssh-%r@%h:%p

    Host sentry ${hosts.sentry.ip} ${hosts.sentry.tailscale}
      HostName ${hosts.sentry.ip}
      User j_kro
      IdentityFile ~/.ssh/id_ed25519_cluster
      IdentitiesOnly yes
      ControlPath ~/.ssh/sockets/ssh-%r@%h:%p

    Host krash2 ${hosts.krash2.ip}
      HostName ${hosts.krash2.ip}
      Port 22
      User krash
      IdentityFile ~/.ssh/id_ed25519_cluster
      IdentitiesOnly yes
      StrictHostKeyChecking accept-new

    Host krash3 10.1.1.150
      HostName 10.1.1.150
      User j_kro
      IdentityFile ~/.ssh/id_ed25519
      IdentitiesOnly yes
      StrictHostKeyChecking accept-new

    Host github.com
      HostName github.com
      User git
      IdentityFile ~/.ssh/id_deploy
      IdentitiesOnly yes
  '';

  systemd.tmpfiles.rules = [
    "d ${userHome}/.ssh/sockets 0700 j_kro users -"
  ];

  networking.firewall.interfaces = {
    tailscale0.allowedTCPPorts = lib.mkOptionDefault [22];
  };
  networking.firewall.extraInputRules = ''
    ip saddr 10.1.1.0/24 tcp dport 22 accept
    iifname "lo" tcp dport 22 accept
  '';
}

# Distributed Build SSH Configuration
# Declaratively manages SSH keys and config for distributed Nix builds
#
# This module:
# 1. Generates SSH keys for distributed builds
# 2. Configures /root/.ssh/config for build machines
# 3. Distributes public keys to j_kro@host for authentication
{ lib, config, pkgs, ... }:
let
  # Host-to-IP mapping for SSH config
  hostIPs = {
    zephyr = "100.81.182.5";
    nexus = "100.86.158.18";
    forge = "100.95.222.45";
    sentry = "100.82.210.39";
  };

  # All build machines except current host
  currentHost = config.networking.hostName;
  remoteHosts = lib.filterAttrs (n: v: n != currentHost) hostIPs;

  # SSH config for all build machines
  sshConfig = lib.concatStringsSep "\n" (lib.mapAttrsToList (host: ip: ''
    Host ${host} ${ip}
      HostName ${ip}
      User j_kro
      IdentityFile /root/.ssh/id_nixbuild
      IdentitiesOnly yes
      StrictHostKeyChecking no
      UserKnownHostsFile /root/.ssh/known_hosts
  '') hostIPs);

  # Public key from zephyr (generated once, distributed to all nodes)
  # In production, this should be managed via agenix or similar
  zephyrPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBrQ6cTBLsgw8N2xKu6S3p7mlBiicKRL39QflEKaJvDl nix-distributed-build";
in
{
  options = {
    services.distributed-builds-ssh.enable = lib.mkEnableOption "SSH configuration for distributed builds";
  };

  config = lib.mkIf config.services.distributed-builds-ssh.enable {
    # Generate SSH key pair for distributed builds
    users.users.root = {
      openssh.authorizedKeys.keys = [ zephyrPublicKey ];
    };

    # Also add to j_kro user for root-to-j_kro SSH
    users.users.j_kro = {
      openssh.authorizedKeys.keys = [ zephyrPublicKey ];
    };

    # Ensure .ssh directory exists
    systemd.tmpfiles.rules = [
      "d /root/.ssh 0700 root root -"
      "d /home/j_kro/.ssh 0700 j_kro users -"
    ];

    # Write SSH config
    environment.etc."root/ssh/config".text = ''
      # Root SSH configuration for distributed builds
      Host *
        StrictHostKeyChecking no
        UserKnownHostsFile /root/.ssh/known_hosts
        ConnectTimeout 5
        ServerAliveInterval 60
        ServerAliveCountMax 3

      # Build machines using nixbuild key
      ${sshConfig}
    '';

    # Set correct permissions on SSH config
    systemd.services.fix-ssh-config-permissions = {
      description = "Fix SSH config permissions";
      wantedBy = [ "multi-user.target" ];
      after = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash -c 'chmod 644 /etc/root/ssh/config && chown root:root /etc/root/ssh/config && mkdir -p /root/.ssh && ln -sf /etc/root/ssh/config /root/.ssh/config'";
      };
    };

    # Ensure the SSH key exists (generate if missing during runtime)
    # Note: In a real setup, keys should be pre-generated and deployed via agenix
    systemd.services.ensure-nixbuild-key = {
      description = "Ensure nixbuild SSH key exists";
      wantedBy = [ "multi-user.target" ];
      after = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.bash}/bin/bash -c 'if [ ! -f /root/.ssh/id_nixbuild ]; then ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f /root/.ssh/id_nixbuild -N \"\" -C \"nix-distributed-build\" 2>/dev/null || true; fi'";
      };
    };
  };
}

{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.networking.cluster;
  hosts = cfg.hosts;

  # Build SSH config for each host
  hostConfigs =
    lib.mapAttrsToList (name: host: ''
      Host ${name}
        Hostname ${host.ip}
        User j_kro
        IdentityFile ~/.ssh/id_ed25519
        ControlPath ~/.ssh/sockets/ssh-%r@%h:%p
        ControlMaster auto
        ControlPersist 600
    '')
    hosts;
in {
  programs.ssh.knownHosts =
    lib.mapAttrs' (
      name: host:
        lib.nameValuePair name {
          hostNames =
            ["${name}" "${name}.cluster.local" host.ip]
            ++ (lib.optional (host ? tailscale) host.tailscale);
          publicKey = host.sshPublicKey or null;
        }
    )
    hosts;

  programs.ssh.extraConfig = lib.concatStringsSep "\n" hostConfigs;
}

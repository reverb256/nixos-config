{ config, lib, pkgs, ... }:
let
  cfg = config.cluster.config;
  hosts = cfg.hosts;
in {
  programs.ssh.knownHosts = lib.mapAttrs' (name: host:
    lib.nameValuePair name {
      hostNames = [ "${name}" "${name}.cluster.local" host.ip ]
        ++ (lib.optional (host ? tailscale) host.tailscale);
      publicKey = host.sshPublicKey or null;
    }
  ) hosts;

  programs.ssh.matchBlocks = lib.mapAttrs' (name: host:
    lib.nameValuePair name {
      hostname = host.ip;
      user = "j_kro";
      identityFile = "~/.ssh/id_ed25519";
      controlPath = "~/.ssh/sockets/ssh-%r@%h:%p";
      controlMaster = "auto";
      controlPersist = "600";
    }
  ) hosts;
}

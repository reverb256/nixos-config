# Cluster Mesh Service Account
#
# Dedicated service account for inter-node SSH mesh (health checks, exec tunneling).
# Replaces root SSH to align with least privilege and cluster policy.
#
# Architecture:
#   - cluster-mesh user/group (uid/gid locked, no interactive shell)
#   - cns-ssh-key owned by cluster-mesh:cluster-mesh 0600 (from agenix)
#   - Systemd service copies key to /var/lib/cluster-mesh/.ssh/id_ed25519
#   - Authorized keys restricted via command= for maximum security
#
# Usage:
#   services.cluster-mesh.enable = true;
#
# SSH usage (service contexts):
#   ssh -i /var/lib/cluster-mesh/.ssh/id_ed25519 cluster-mesh@10.1.1.X <command>
#
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.services.cluster-mesh;
  inherit (lib) mkEnableOption mkIf mkOption types;

  # Cluster node IPs
  clusterNodes = {
    zephyr = "10.1.1.110";
    nexus = "10.1.1.120";
    forge = "10.1.1.130";
    sentry = "10.1.1.140";
  };
in {
  options.services.cluster-mesh = {
    enable = mkEnableOption "Cluster mesh service account for inter-node SSH";

    sshKey = mkOption {
      type = types.str;
      default = "/run/secrets/cns-ssh-key";
      description = "Path to CNS SSH key (agenix-deployed)";
    };

    keyDir = mkOption {
      type = types.path;
      default = "/var/lib/cluster-mesh/.ssh";
      description = "Directory for cluster-mesh SSH key (copied from agenix)";
    };
  };

  config = mkIf cfg.enable {
    # Create cluster-mesh user/group
    users.users.cluster-mesh = {
      description = "Cluster mesh service account for inter-node SSH";
      isSystemUser = true;
      group = "cluster-mesh";
      shell = "${pkgs.shadow}/bin/nologin";
    };

    users.groups.cluster-mesh = {};

    # Agenix secret: cns-ssh-key owned by cluster-mesh
    age.secrets.cns-ssh-key = {
      file = "${inputs.self}/secrets/cns-ssh-key.age";
      mode = "600";
      owner = "cluster-mesh";
      group = "cluster-mesh";
    };

    # Systemd service: copy key from /run/agenix to persistent location
    systemd.services.cluster-mesh-key-setup = {
      description = "Setup cluster-mesh SSH key from agenix";
      after = ["agenix.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;

        # Create key directory with correct ownership
        ExecStartPre = pkgs.writeShellScript "cluster-mesh-key-setup-pre" ''
          mkdir -p ${cfg.keyDir}
          chown cluster-mesh:cluster-mesh ${cfg.keyDir}
          chmod 700 ${cfg.keyDir}
        '';

        # Copy key from agenix
        ExecStart = pkgs.writeShellScript "cluster-mesh-key-setup" ''
          cp ${cfg.sshKey} ${cfg.keyDir}/id_ed25519
          chmod 600 ${cfg.keyDir}/id_ed25519
          chown cluster-mesh:cluster-mesh ${cfg.keyDir}/id_ed25519
        '';
      };
    };

    # Authorized keys: restricted via command=
    users.users.cluster-mesh.openssh.authorizedKeys.keys = [
      # CNS health check command whitelist
      "command=\"${pkgs.openssh}/bin/ssh -i ${cfg.keyDir}/id_ed25519 cluster-mesh@10.1.1.110 hostname\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAv...zephyr"
      "command=\"${pkgs.openssh}/bin/ssh -i ${cfg.keyDir}/id_ed25519 cluster-mesh@10.1.1.120 hostname\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAv...nexus"
      "command=\"${pkgs.openssh}/bin/ssh -i ${cfg.keyDir}/id_ed25519 cluster-mesh@10.1.1.130 hostname\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAv...forge"
      "command=\"${pkgs.openssh}/bin/ssh -i ${cfg.keyDir}/id_ed25519 cluster-mesh@10.1.1.140 hostname\" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAv...sentry"
    ];
  };
}

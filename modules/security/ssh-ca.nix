{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.services.ssh-ca;
  inherit (lib) mkOption types mkIf;

  caPubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFvnb27DcSRHhd/GExh+djB2AlGg+IlNR3cktVTuEIZu";
in {
  options.services.ssh-ca = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable SSH CA for cluster host authentication";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.ssh-ca-sign-host = {
      description = "Sign SSH host key with cluster CA";
      wantedBy = ["multi-user.target"];
      before = ["sshd.service"];
      after = ["agenix.service"];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = ''
        set -euo pipefail
        KEY=/etc/ssh/ssh_host_ed25519_key
        CERT=/etc/ssh/ssh_host_ed25519_key-cert.pub
        CA_KEY=/run/secrets/ssh-ca-key
        HOSTNAME=${config.networking.hostName}
        if [ ! -f "$CA_KEY" ]; then echo "SSH CA key not available"; exit 0; fi
        REGEN=false
        [ ! -f "$CERT" ] && REGEN=true
        ${lib.getExe' pkgs.openssh "ssh-keygen"} -L -f "$CERT" 2>/dev/null | grep -q "$HOSTNAME" || REGEN=true
        if [ "$REGEN" = true ]; then
          ${lib.getExe' pkgs.openssh "ssh-keygen"} -s "$CA_KEY" \
            -I "$HOSTNAME.cluster.local" -h -n "$HOSTNAME,$HOSTNAME.lan" \
            -V "+52w" "$KEY.pub" 2>/dev/null
          chmod 644 "$CERT"
          echo "Signed host key for $HOSTNAME"
        fi
      '';
    };

    # @cert-authority via structured option
    programs.ssh.knownHosts = {
      "cluster-ca" = {
        hostNames = [
          "*.lan"
          "*.cluster.local"
          "*.taila21e09.ts.net"
          "10.1.1.*"
          "100.*"
        ];
        publicKey = caPubKey;
        certAuthority = true;
      };
    };
  };
}

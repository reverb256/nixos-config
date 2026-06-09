{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.ssh-ca;
  inherit (lib) mkOption types mkIf;
in {
  options.services.ssh-ca = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable SSH CA for cluster host authentication";
    };
  };

  config = mkIf cfg.enable {
    # ── 1. Sign host key with CA (if CA private key available) ──
    systemd.services.ssh-ca-sign-host = {
      description = "Sign SSH host key with cluster CA";
      wantedBy = ["multi-user.target"];
      before = ["sshd.service"];
      after = ["cluster-ca-init.service"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -euo pipefail
        KEY=/etc/ssh/ssh_host_ed25519_key
        CERT=/etc/ssh/ssh_host_ed25519_key-cert.pub
        CA_KEY=/etc/ssl/cluster-ca/ca.key
        HOSTNAME=${config.networking.hostName}

        if [ ! -f "$CA_KEY" ]; then
          echo "CA key not found — host cert signing deferred"
          exit 0
        fi

        REGEN=false
        if [ ! -f "$CERT" ]; then
          REGEN=true
        elif ! ${pkgs.openssh}/bin/ssh-keygen -L -f "$CERT" 2>/dev/null | grep -q "$HOSTNAME"; then
          REGEN=true
        fi

        if [ "$REGEN" = true ]; then
          ${pkgs.openssh}/bin/ssh-keygen -s "$CA_KEY" \
            -I "$HOSTNAME.cluster.local" \
            -h -n "$HOSTNAME,$HOSTNAME.lan" \
            -V "+52w" "$KEY.pub" 2>/dev/null
          chmod 644 "$CERT"
          echo "SSH host key signed for $HOSTNAME"
        fi
      '';
    };

    programs.ssh.extraConfig = lib.mkAfter ''
      # SSH CA: trust cluster CA for all *.lan hosts
    '';
  };
}

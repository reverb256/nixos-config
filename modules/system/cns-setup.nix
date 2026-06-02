{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf getExe;
in {
  options.services.cns-setup = {
    enable = mkEnableOption "CNS initial setup helper (Zephyr only)";
  };

  config = mkIf config.services.cns-setup.enable {
    systemd.services.cns-setup = {
      description = "CNS: Generate SSH keys if missing";
      wantedBy = ["multi-user.target"];
      before = ["cns-watcher.service"];
      serviceConfig = {
        ExecStart = pkgs.writeShellScript "cns-setup" ''
          set -euo pipefail

          SSH_KEY="/run/agenix/cns-ssh-key"

          if [ ! -f "$SSH_KEY" ]; then
            echo "Generating CNS SSH key..."
            ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "cns@zephyr"
            chmod 600 "$SSH_KEY"
            chmod 644 "$SSH_KEY.pub"
            echo "CNS SSH key generated at $SSH_KEY"
            echo "Public key: $SSH_KEY.pub"
            echo ""
            echo "Add this to cns-receiver.sshPublicKey on all nodes:"
            cat "$SSH_KEY.pub"
          else
            echo "CNS SSH key already exists"
          fi
        '';
        Type = "oneshot";
        User = "root";
        Group = "root";
      };
    };
  };
}

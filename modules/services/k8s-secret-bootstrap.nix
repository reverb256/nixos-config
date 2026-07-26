{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.k8s-secret-bootstrap;
in {
  options.services.k8s-secret-bootstrap = {
    enable = lib.mkEnableOption "Auto-generate K8s secrets on first deploy";

    secrets = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          namespace = lib.mkOption {type = lib.types.str;};
          name = lib.mkOption {type = lib.types.str;};
          keys = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = "Keys to generate (each gets a 32-char random base64 value)";
          };
        };
      });
      default = [];
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.k8s-secret-bootstrap = {
      description = "Bootstrap K8s secrets (create if missing)";
      after = ["k3s.service"];
      requires = ["k3s.service"];
      before = ["k8s-nix-deploy.service"];
      wantedBy = [];
      serviceConfig = {
        Type = "oneshot";
        Environment = "KUBECONFIG=/etc/rancher/k3s/k3s.yaml";
        RemainAfterExit = true;
      };
      path = [pkgs.kubectl pkgs.openssl pkgs.coreutils];
      script = ''
        set -euo pipefail

        echo "[k8s-secret-bootstrap] Waiting for K8s API..."
        elapsed=0
        until kubectl get nodes &>/dev/null; do
          sleep 5
          elapsed=$((elapsed + 5))
          if [ $elapsed -ge 120 ]; then
            echo "[k8s-secret-bootstrap] Timed out waiting for K8s API"
            exit 1
          fi
        done

        ${lib.concatMapStrings (secret: ''
            if kubectl get secret ${secret.name} -n ${secret.namespace} &>/dev/null; then
              echo "[k8s-secret-bootstrap] Secret ${secret.name} already exists"
            else
              echo "[k8s-secret-bootstrap] Generating secret ${secret.name}..."
              # Generate all key-values inline — avoids bash variable naming issues with hyphens
              kubectl create secret generic ${secret.name} -n ${secret.namespace} \
                ${lib.concatMapStrings (key: ''
                --from-literal=${key}="$(openssl rand -base64 32 | head -c 32)" \
              '')
              secret.keys}
              echo "[k8s-secret-bootstrap] Created ${secret.name}"
            fi
          '')
          cfg.secrets}

        echo "[k8s-secret-bootstrap] Done."
      '';
    };

  };
}

{ config, lib, pkgs, ... }:

let
  cfg = config.services.cluster-ca;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.cluster-ca = {
    enable = mkEnableOption "Internal CA for cluster services";

    domain = mkOption {
      type = types.str;
      default = "cluster.local";
      description = "Domain for the internal CA";
    };

    caCert = mkOption {
      type = types.path;
      default = "/etc/ssl/cluster-ca/ca.crt";
      description = "Path to CA certificate";
    };

    caKey = mkOption {
      type = types.path;
      default = "/etc/ssl/cluster-ca/ca.key";
      description = "Path to CA private key";
    };
  };

  config = mkIf cfg.enable {
    # Create CA certificate and key
    systemd.services.cluster-ca-init = {
      description = "Generate internal CA certificate";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = "/etc/ssl/cluster-ca";
        StateDirectory = "cluster-ca";
        StateDirectoryMode = "0755";
      };
      script = ''
        # Generate CA certificate if it doesn't exist
        if [ ! -f ${cfg.caCert} ]; then
          ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:4096 \
            -keyout ${cfg.caKey} \
            -out ${cfg.caCert} \
            -days 3650 \
            -nodes \
            -subj "/C=US/ST=State/L=City/O=Cluster/CN=Cluster CA" \
            -addext "subjectAltName=DNS:cluster.local,DNS:*.cluster.local"

          echo "Internal CA certificate generated at ${cfg.caCert}"
          chmod 644 ${cfg.caCert}
          chmod 600 ${cfg.caKey}
        else
          echo "CA certificate already exists at ${cfg.caCert}"
        fi
      '';
    };

    # Expose CA certificate for browsers
    systemd.services.cluster-ca-export = {
      description = "Export CA certificate to user home";
      wantedBy = [ "multi-user.target" ];
      after = [ "cluster-ca-init.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "j_kro";
      };
      script = ''
        # Export CA cert to user's home directory for browser import
        mkdir -p /home/j_kro/.local/share/certificates
        cp ${cfg.caCert} /home/j_kro/.local/share/certificates/cluster-ca.crt
        chown j_kro:users /home/j_kro/.local/share/certificates/cluster-ca.crt
        echo "CA certificate exported to /home/j_kro/.local/share/certificates/cluster-ca.crt"
      '';
    };
  };
}

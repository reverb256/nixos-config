{
  config,
  lib,
  pkgs,
  ...
}: let
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

  config =
    mkIf cfg.enable {
      # Install CA into system trust store via NixOS declarative mechanism
      # (runtime approaches like /etc/pki/ca-trust fail on NixOS — /etc is read-only)
      security.pki.certificateFiles = [ ./../../certs/cluster-ca.crt ];

      # Point Python (certifi/requests/httpx) at the system CA bundle so that
      # apps like Hermes Agent trust the Cluster CA for *.lan endpoints.
      # The system bundle is a superset of certifi's own CAs + our Cluster CA.
      environment.variables = {
        SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
        REQUESTS_CA_BUNDLE = "/etc/ssl/certs/ca-bundle.crt";
      };

      systemd.services.cluster-ca-init = {
        description = "Generate internal CA certificate and update trust store";
        wantedBy = ["multi-user.target"];
        before = ["caddy.service"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          StateDirectory = "cluster-ca";
          StateDirectoryMode = "0755";
        };
        script = ''
          if [ ! -f ${cfg.caCert} ]; then
            mkdir -p /etc/ssl/cluster-ca
            ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:4096 \
              -keyout ${cfg.caKey} \
              -out ${cfg.caCert} \
              -days 3650 \
              -nodes \
              -subj "/C=US/ST=State/L=City/O=Cluster/CN=Cluster CA" \
              -addext "basicConstraints=critical,CA:TRUE" \
              -addext "keyUsage=critical,keyCertSign,cRLSign" \
              -addext "subjectAltName=DNS:*.lan,DNS:*.cluster.local,DNS:auth.lan,DNS:mission-control.lan,DNS:kagent.lan,DNS:mc.cluster.local,DNS:privacy-filter.lan,DNS:search.lan,DNS:ai.lan,DNS:ai-inference.lan,DNS:openwebui.lan,DNS:haven.lan,DNS:hermes.lan,DNS:api.hermes.lan,DNS:n8n.lan,DNS:activepieces.lan,DNS:searxng.lan,DNS:brain.lan,DNS:qdrant.lan,DNS:knowledge-fabric.lan,DNS:monitoring.lan,DNS:grafana.lan,DNS:prometheus.lan,DNS:llama.zephyr.lan,DNS:llama.sentry.lan,DNS:workspace.lan" 2>/dev/null

            echo "Internal CA certificate generated at ${cfg.caCert}"
            chmod 644 ${cfg.caCert}
            chmod 640 ${cfg.caKey}
            chown root:caddy ${cfg.caKey}
          else
            echo "CA certificate already exists at ${cfg.caCert}"
            # Ensure permissions are correct on existing key
            chmod 640 ${cfg.caKey}
            chown root:caddy ${cfg.caKey} 2>/dev/null || true
          fi

          # Generate leaf certificate for Caddy (covers all .lan domains)
          LEAF_CERT=/etc/ssl/cluster-ca/leaf.crt
          LEAF_KEY=/etc/ssl/cluster-ca/leaf.key
          if [ ! -f $LEAF_CERT ] || ! ${pkgs.openssl}/bin/openssl x509 -in $LEAF_CERT -noout -checkend 2592000 2>/dev/null; then
            ${pkgs.openssl}/bin/openssl genrsa -out $LEAF_KEY 2048 2>/dev/null
            ${pkgs.openssl}/bin/openssl req -new -key $LEAF_KEY -out /tmp/leaf.csr \
              -subj "/CN=Cluster Ingress" \
            -addext "subjectAltName=DNS:*.lan,DNS:*.cluster.local,DNS:auth.lan,DNS:mission-control.lan,DNS:kagent.lan,DNS:mc.cluster.local,DNS:privacy-filter.lan,DNS:search.lan,DNS:ai.lan,DNS:ai-inference.lan,DNS:openwebui.lan,DNS:haven.lan,DNS:hermes.lan,DNS:api.hermes.lan,DNS:n8n.lan,DNS:activepieces.lan,DNS:searxng.lan,DNS:brain.lan,DNS:qdrant.lan,DNS:knowledge-fabric.lan,DNS:monitoring.lan,DNS:grafana.lan,DNS:prometheus.lan,DNS:llama.zephyr.lan,DNS:llama.sentry.lan,DNS:workspace.lan" 2>/dev/null
            ${pkgs.openssl}/bin/openssl x509 -req -in /tmp/leaf.csr -CA ${cfg.caCert} -CAkey ${cfg.caKey} \
              -CAcreateserial -out $LEAF_CERT -days 365 -copy_extensions copyall 2>/dev/null
            rm -f /tmp/leaf.csr
            chmod 644 $LEAF_CERT
            chmod 640 $LEAF_KEY
            chown root:caddy $LEAF_KEY
            echo "Leaf certificate generated at $LEAF_CERT"
          else
            echo "Leaf certificate still valid"
          fi

        '';
      };

      systemd.services.cluster-ca-export = {
        description = "Export CA certificate to user home";
        wantedBy = ["multi-user.target"];
        after = ["cluster-ca-init.service"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "j_kro";
        };
        script = ''
          mkdir -p /home/j_kro/.local/share/certificates
          cp ${cfg.caCert} /home/j_kro/.local/share/certificates/cluster-ca.crt
          chown j_kro:users /home/j_kro/.local/share/certificates/cluster-ca.crt
          echo "CA certificate exported to /home/j_kro/.local/share/certificates/cluster-ca.crt"
        '';
      };
    };
}


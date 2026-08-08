{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.cluster-ca;

  inherit (lib) mkEnableOption mkOption types mkIf;

  # ── Derive SANs from clusterNetworking.lanDomains (SSOT) ──
  # cluster-dns.nix populates lanDomains from its service lists.
  # Adding a domain in cluster-dns.nix automatically adds it to
  # DNS records AND the leaf certificate SANs. No manual duplication.
  lanDomains = config.clusterNetworking.lanDomains or [];

  # Base domains that always appear in SANs (wildcards + K8s)
  baseDomains = ["*.lan" "*.cluster.local"];

  # Combine base + service domains + any extra per-host domains
  allDomains = baseDomains ++ lanDomains ++ cfg.extraDomains;

  # Build the SAN string: "DNS:*.lan,DNS:auth.lan,..."
  commonSANS = lib.concatStringsSep "," (
    map (d: "DNS:${d}") allDomains
  );

  openssl = "${pkgs.openssl}/bin/openssl";

  # ── Build CA subject string from config ──
  # Produces: /C=CA/O=reverb256/CN=reverb256 Internal CA
  # Empty fields (state, locality) are omitted to keep subject clean.
  caSubjectParts = lib.filter (s: s != "") [
    "/C=${cfg.caSubject.country}"
    (lib.optionalString (cfg.caSubject.state != "") "/ST=${cfg.caSubject.state}")
    (lib.optionalString (cfg.caSubject.locality != "") "/L=${cfg.caSubject.locality}")
    "/O=${cfg.caSubject.organization}"
    "/CN=${cfg.caSubject.commonName}"
  ];
  caSubjectString = lib.concatStringsSep "" caSubjectParts;

  # Hash of the current SAN list — changes when domains are added/removed.
  # Stored in /etc/ssl/cluster-ca/.san-hash to detect drift.
  # If the hash doesn't match, the leaf cert is regenerated automatically.
  sanHash = builtins.hashString "sha256" commonSANS;
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
      description = "Path to the provisioned CA private key";
    };

    caKeyProvisioned = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether the CA private key is provisioned by a secret manager.
        When true, the service fails closed if the key is absent instead of
        generating a key that cannot match the static CA certificate.
      '';
    };

    caKeyService = mkOption {
      type = types.str;
      default = "sops-install-secrets.service";
      description = ''
        Systemd unit that provisions the CA private key when
        <option>caKeyProvisioned</option> is true. Defaults to sops-nix;
        hosts that use SecretSpec provisioning (e.g. nexus) must override
        this to "secretspec-creds.service".
      '';
    };

    allowGenerateCa = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Allow first-boot generation of a new CA when no static CA exists.
        Keep false for the fleet so hosts cannot silently fork the trust root.
      '';
    };

    leafCert = mkOption {
      type = types.path;
      default = "/etc/ssl/cluster-ca/leaf.crt";
      description = "Path to leaf certificate";
    };

    leafKey = mkOption {
      type = types.path;
      default = "/etc/ssl/cluster-ca/leaf.key";
      description = "Path to leaf private key";
    };

    # Extra domains beyond what cluster-dns.nix provides
    extraDomains = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["llama.zephyr.lan" "brain.lan"];
      description = "Additional domains to include in leaf cert SANs (beyond auto-derived list from cluster-dns.nix)";
    };

    # Whether to install the CA into the system trust store
    installTrust = mkOption {
      type = types.bool;
      default = true;
      description = "Install CA certificate into system trust store";
    };

    # Whether to generate a leaf cert (only needed on Caddy hosts)
    generateLeaf = mkOption {
      type = types.bool;
      default = true;
      description = "Generate leaf certificate signed by the CA (needed for Caddy/TLS termination)";
    };

    # Group that should own the private keys
    keyGroup = mkOption {
      type = types.str;
      default = "caddy";
      description = "Group that gets read access to private keys";
    };

    # ── CA certificate subject fields (cosmetic — shown in cert details) ──
    caSubject = mkOption {
      type = types.submodule {
        options = {
          country = mkOption {
            type = types.str;
            default = "CA";
            description = "Country code (ISO 3166-1 alpha-2)";
          };
          state = mkOption {
            type = types.str;
            default = "";
            description = "State or province";
          };
          locality = mkOption {
            type = types.str;
            default = "";
            description = "City or locality";
          };
          organization = mkOption {
            type = types.str;
            default = "reverb256";
            description = "Organization name";
          };
          commonName = mkOption {
            type = types.str;
            default = "reverb256 Internal CA";
            description = "Common Name (displayed by browsers/tools)";
          };
        };
      };
      default = {};
      description = "X.509 subject fields for the internal CA certificate. These are cosmetic — displayed in certificate inspectors but do not affect trust validation.";
      example = {
        country = "CA";
        state = "British Columbia";
        locality = "Vancouver";
        organization = "reverb256";
        commonName = "reverb256 Cluster CA";
      };
    };
  };

  config = mkIf cfg.enable {
    # Install CA into system trust store via NixOS declarative mechanism
    # This makes all .lan HTTPS endpoints trusted on this host
    security.pki.certificateFiles = mkIf cfg.installTrust [./../../certs/cluster-ca.crt];

    # Point Python (certifi/requests/httpx) and Go at the system CA bundle so that
    # apps (Hermes Agent, kubectl) trust the Cluster CA for *.lan endpoints.
    environment.variables = mkIf cfg.installTrust {
      SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
      REQUESTS_CA_BUNDLE = "/etc/ssl/certs/ca-bundle.crt";
    };

    # Also set via PAM so sudo/kubectl inherit these — sudo strips environment.variables
    environment.sessionVariables = mkIf cfg.installTrust {
      SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
      REQUESTS_CA_BUNDLE = "/etc/ssl/certs/ca-bundle.crt";
    };

    systemd.services.cluster-ca-init = {
      description = "Generate internal CA certificate and leaf cert";
      wantedBy = ["multi-user.target"];
      before = ["caddy.service"];
      after = lib.optional cfg.caKeyProvisioned cfg.caKeyService;
      wants = lib.optional cfg.caKeyProvisioned cfg.caKeyService;
      requires = lib.optional cfg.caKeyProvisioned cfg.caKeyService;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "cluster-ca";
        StateDirectoryMode = "0755";
      };
      script = ''
        STATIC_CA="${./../../certs/cluster-ca.crt}"
        SAN_HASH="${sanHash}"
        SAN_FILE="/etc/ssl/cluster-ca/.san-hash"

        mkdir -p /etc/ssl/cluster-ca

        # ── CA Certificate ──────────────────────────────────────
        # The repository certificate is the fleet trust anchor. Replace any
        # stale locally-generated certificate so hosts cannot silently fork
        # the cluster PKI. Never generate a new key for an existing CA.
        if [ -f "$STATIC_CA" ]; then
          if [ ! -f ${cfg.caCert} ] || ! cmp -s "$STATIC_CA" ${cfg.caCert}; then
            echo "Installing canonical cluster CA certificate"
            cp "$STATIC_CA" ${cfg.caCert}
            chmod 644 ${cfg.caCert}
            ${lib.optionalString cfg.generateLeaf ''
            rm -f ${cfg.leafCert} ${cfg.leafKey} /etc/ssl/cluster-ca/fullchain.crt "$SAN_FILE"
            ''}
          fi
        elif ! ${lib.boolToString cfg.allowGenerateCa}; then
          echo "ERROR: canonical cluster CA certificate is unavailable; refusing to generate a trust-root fork" >&2
          exit 1
        elif [ ! -f ${cfg.caCert} ]; then
          ${openssl} req -x509 -newkey rsa:4096 \
            -keyout ${cfg.caKey} \
            -out ${cfg.caCert} \
            -days 3650 \
            -nodes \
            -subj "${caSubjectString}" \
            -addext "basicConstraints=critical,CA:TRUE" \
            -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null
          chmod 644 ${cfg.caCert}
        fi

        if ${lib.boolToString cfg.generateLeaf}; then
          if [ ! -s ${cfg.caKey} ]; then
            echo "ERROR: CA private key ${cfg.caKey} is missing; refusing to mint leaf certificates" >&2
            exit 1
          fi
          key_hash=$(${openssl} pkey -in ${cfg.caKey} -pubout 2>/dev/null | ${openssl} pkey -pubin -outform DER 2>/dev/null | sha256sum | cut -d' ' -f1)
          cert_hash=$(${openssl} x509 -in ${cfg.caCert} -pubkey -noout 2>/dev/null | ${openssl} pkey -pubin -outform DER 2>/dev/null | sha256sum | cut -d' ' -f1)
          if [ -z "$key_hash" ] || [ "$key_hash" != "$cert_hash" ]; then
            echo "ERROR: CA private key does not match ${cfg.caCert}; refusing to mint leaf certificates" >&2
            exit 1
          fi
          chmod 0400 ${cfg.caKey}
          chown root:root ${cfg.caKey}
        fi

        # ── Leaf Certificate ────────────────────────────────────
        ${lib.optionalString cfg.generateLeaf ''
          LEAF_CERT=${cfg.leafCert}
          LEAF_KEY=${cfg.leafKey}
          REGEN=false

          # Regenerate if: cert missing, expiring within 30 days, OR SANs changed
          if [ ! -f $LEAF_CERT ]; then
            echo "Leaf cert missing — generating"
            REGEN=true
          elif ! ${openssl} x509 -in $LEAF_CERT -noout -checkend 2592000 2>/dev/null; then
            echo "Leaf cert expiring soon — regenerating"
            REGEN=true
          elif [ ! -f "$SAN_FILE" ] || [ "$(cat $SAN_FILE)" != "$SAN_HASH" ]; then
            echo "SANs changed — regenerating leaf cert"
            REGEN=true
          else
            echo "Leaf certificate still valid and SANs unchanged"
            # Ensure fullchain exists even if leaf was not regenerated
            if [ ! -f /etc/ssl/cluster-ca/fullchain.crt ]; then
              cat $LEAF_CERT ${cfg.caCert} > /etc/ssl/cluster-ca/fullchain.crt
              chmod 644 /etc/ssl/cluster-ca/fullchain.crt
            fi
          fi

          if [ "$REGEN" = true ]; then
            ${openssl} genrsa -out $LEAF_KEY 2048 2>/dev/null
            ${openssl} req -new -key $LEAF_KEY -out /tmp/leaf.csr \
              -subj "/CN=Cluster Ingress" \
              -addext "subjectAltName=${commonSANS}" 2>/dev/null
            ${openssl} x509 -req -in /tmp/leaf.csr \
              -CA ${cfg.caCert} -CAkey ${cfg.caKey} \
              -CAcreateserial -out $LEAF_CERT \
              -days 365 -copy_extensions copyall 2>/dev/null
            rm -f /tmp/leaf.csr
            chmod 644 $LEAF_CERT
            chmod 640 $LEAF_KEY
              chown root:${cfg.keyGroup} $LEAF_KEY
              chown root:${cfg.keyGroup} $LEAF_CERT
              chmod 644 $LEAF_CERT
              chmod 640 $LEAF_KEY
              echo "$SAN_HASH" > "$SAN_FILE"
            echo "Leaf certificate generated at $LEAF_CERT"

            # Generate fullchain (leaf + CA) for proper TLS chain
            cat $LEAF_CERT ${cfg.caCert} > /etc/ssl/cluster-ca/fullchain.crt
            chmod 644 /etc/ssl/cluster-ca/fullchain.crt
            echo "Full chain generated at /etc/ssl/cluster-ca/fullchain.crt"
          fi
        ''}
      '';
    };

    # Caddy must not start before the leaf certificate and key exist.
    systemd.services.caddy = lib.mkIf cfg.generateLeaf {
      after = ["cluster-ca-init.service"];
      requires = ["cluster-ca-init.service"];
    };

    # Caddy needs the leaf key, never the CA signing key.
    users.users.caddy = lib.mkIf (config.services.caddy.enable or false) {
      isSystemUser = true;
      group = "caddy";
      extraGroups = [cfg.keyGroup];
    };
    users.groups.caddy = {};

    systemd.services.cluster-ca-export = {
      description = "Export CA certificate to user home";
      wantedBy = ["multi-user.target"];
      after = ["cluster-ca-init.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "j_kro";
        ExecStart = pkgs.writeShellScript "cluster-ca-export" ''
          mkdir -p ~/.local/share/ca-certificates
          cp ${cfg.caCert} ~/.local/share/ca-certificates/cluster-ca.crt
          update-ca-certificates 2>/dev/null || true
          echo "CA certificate exported to ~/.local/share/ca-certificates/"
        '';
      };
    };
    # Ensure cert directory exists and has correct permissions
    systemd.tmpfiles.rules =
      ["d /etc/ssl/cluster-ca 0755 root root -"]
      ++ lib.optional cfg.generateLeaf "f /etc/ssl/cluster-ca/leaf.key 0640 root ${cfg.keyGroup} -"
      ++ ["f /etc/ssl/cluster-ca/leaf.crt 0644 root root -"];
  };
}

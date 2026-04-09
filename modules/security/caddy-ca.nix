# Caddy Ingress Local CA Certificate
# Trusts the Caddy internal CA for cluster ingress services
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.security.caddyCa;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.security.caddyCa = {
    enable = mkEnableOption "Trust Caddy Ingress local CA certificate";

    certificate = mkOption {
      type = types.path;
      default = ./../../certs/caddy-root-ca.crt;
      description = "Path to Caddy root CA certificate file";
    };
  };

  config = mkIf cfg.enable {
    # Add Caddy CA to system trust store
    security.pki.certificateFiles = [cfg.certificate];

    # Ensure certificate is readable
    system.activationScripts.caddyCa = ''
      # Add openssl to PATH for activation script
      export PATH="${pkgs.openssl}/bin:$PATH"

      # Display certificate info for verification
      echo "✓ Caddy CA certificate installed and trusted"
      openssl x509 -in "${cfg.certificate}" -noout -subject -issuer -dates || echo "  (Certificate info unavailable)"
    '';
  };
}

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
    security.pki.certificateFiles = [cfg.certificate];

    system.activationScripts.caddyCa = ''
      export PATH="${pkgs.openssl}/bin:$PATH"

      echo "✓ Caddy CA certificate installed and trusted"
      openssl x509 -in "${cfg.certificate}" -noout -subject -issuer -dates || echo "  (Certificate info unavailable)"
    '';
  };
}

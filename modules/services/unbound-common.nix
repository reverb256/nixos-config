{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkIf mkOption types;
  cfg = config.services.unbound-common;
in {
  options.services.unbound-common = {
    enable = lib.mkEnableOption "Unbound DNS resolver with DNS-over-TLS (cluster-wide config)";
  };

  config = mkIf cfg.enable {
    services.unbound = {
      enable = lib.mkDefault true;

      settings = {
        # Minimal server block — cluster-dns.nix (on zephyr) extends this with
        # additional interfaces, access-control ranges, and local DNS records.
        server = {
          # interface not set here — cluster-dns.nix provides per-host interfaces
          access-control = ["127.0.0.0/8 allow"];
          hide-identity = true;
          hide-version = true;
          tls-cert-bundle = "/etc/ssl/certs/ca-bundle.crt";
        };

        # Forward zones NOT defined here — cluster-dns.nix provides them on
        # hosts that include cluster networking (nexus, forge, sentry).
        # On hosts without cluster networking, unbound-common currently has
        # no forward-zone requirement. Duplicate forward zones are ignored
        # by unbound (logs a warning) but are still sloppy.
      };
    };

    networking.firewall.allowedUDPPorts = lib.mkOptionDefault [53];
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [53];

    networking.firewall.extraInputRules = lib.mkAfter ''
      ip saddr { 10.1.1.0/24, 10.42.0.0/16 } udp dport 53 accept
      ip saddr { 10.1.1.0/24, 10.42.0.0/16 } tcp dport 53 accept
    '';
  };
}

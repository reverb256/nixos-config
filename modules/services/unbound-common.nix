{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkIf mkOption types;
  cluster = config.networking.cluster;
  cfg = config.services.unbound-common;
in {
  options.services.unbound-common = {
    enable = lib.mkEnableOption "Unbound DNS resolver with DNS-over-TLS (cluster-wide config)";
  };

  config = mkIf cfg.enable {
    services.unbound = {
      enable = true;

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

        forward-zone = [
          {
            name = "ts.net.";
            forward-addr = ["100.100.100.100" "fd7a:115c:a1e0::53"];
          }
          {
            name = ".";
            forward-addr = [
              "1.1.1.1@853"
              "1.0.0.1@853"
              "8.8.8.8@853"
              "8.8.4.4@853"
            ];
            forward-tls-upstream = true;
          }
        ];
      };
    };

    networking.firewall.allowedUDPPorts = lib.mkOptionDefault [53];
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [53];

    networking.firewall.extraInputRules = lib.mkAfter ''
      ip saddr { 10.1.1.0/24, 10.244.0.0/16 } udp dport 53 accept
      ip saddr { 10.1.1.0/24, 10.244.0.0/16 } tcp dport 53 accept
    '';
  };
}

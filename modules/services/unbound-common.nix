{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf mkOption types;
  cfg = config.clusterNetworking;
in
{
  options.services.unbound-common = {
    enable = lib.mkEnableOption "Unbound DNS resolver with DNS-over-TLS (cluster-wide config)";
  };

  config = mkIf cfg.enable {
    services.unbound = {
      enable = true;

      settings = {
        server = {
          interface = [
            "127.0.0.1"
            cfg.ipAddress
          ];
          access-control = [
            "127.0.0.0/8 allow"
            "10.1.1.0/24 allow"
            "10.244.0.0/16 allow"
          ];
          num-threads = 4;
          msg-cache-size = "128m";
          rrset-cache-size = "128m";
          hide-identity = true;
          hide-version = true;
          tls-cert-bundle = "/etc/ssl/certs/ca-bundle.crt";
          include = [ "/etc/unbound/local-dns.conf" ];
        };

        forward-zone = [
          {
            name = "ts.net.";
            forward-addr = [ "100.100.100.100" "fd7a:115c:a1e0::53" ];
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

    environment.etc."unbound/local-dns.conf".text =
      lib.concatMapStrings (record: "local-data: \"${record}\"\n")
        [
          # Cluster hostnames
          "zephyr.lan. IN A 10.1.1.110"
          "nexus.lan. IN A 10.1.1.120"
          "forge.lan. IN A 10.1.1.130"
          "sentry.lan. IN A 10.1.1.140"
          "seeker.lan. IN A 100.84.24.43"

          # Service DNS — all services terminate TLS on nexus
          "search.lan. IN A 10.1.1.120"
          "ai.lan. IN A 10.1.1.120"
          "openwebui.lan. IN A 10.1.1.120"
          "haven.lan. IN A 10.1.1.120"
          "hermes.lan. IN A 10.1.1.120"
          "api.hermes.lan. IN A 10.1.1.120"
          "n8n.lan. IN A 10.1.1.120"
          "searxng.lan. IN A 10.1.1.120"
          "activepieces.lan. IN A 10.1.1.120"
        ];

    networking.firewall.allowedUDPPorts = lib.mkOptionDefault [ 53 ];
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ 53 ];

    networking.firewall.extraInputRules = lib.mkAfter ''
      ip saddr { 10.1.1.0/24, 10.244.0.0/16 } udp dport 53 accept
      ip saddr { 10.1.1.0/24, 10.244.0.0/16 } tcp dport 53 accept
    '';
  };
}

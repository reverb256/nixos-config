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
          include = "/etc/unbound/local-dns.conf";
        };

        forward-zone = [
          {
            name = ".";
            forward-addr = [
              "1.1.1.1"
              "1.0.0.1"
              "8.8.8.8"
              "8.8.4.4"
            ];
          }
        ];
      };
    };

    environment.etc."unbound/local-dns.conf".text =
      lib.concatMapStrings (record: "local-data: \"${record}\"\n")
        [
          "search.lan. IN A 10.1.1.100"
          "ai.lan. IN A 10.1.1.100"
          "openwebui.lan. IN A 10.1.1.100"
          "search.cluster.local. IN A 10.1.1.100"
          "ai.cluster.local. IN A 10.1.1.100"
          "openwebui.cluster.local. IN A 10.1.1.100"
          "haven.lan. IN A 10.1.1.120"
          "haven.cluster.local. IN A 10.1.1.120"
          "hermes.lan. IN A 10.1.1.120"
          "hermes.cluster.local. IN A 10.1.1.120"
          "api.hermes.lan. IN A 10.1.1.120"
          "brain.cluster.local. IN A 10.1.1.120"
          "n8n.lan. IN A 10.1.1.100"
          "searxng.lan. IN A 10.1.1.100"
          "activepieces.lan. IN A 10.1.1.100"
          "studio.lan. IN A 10.1.1.100"
          "studio.cluster.local. IN A 10.1.1.100"
          "n8n.cluster.local. IN A 10.1.1.100"
          "activepieces.cluster.local. IN A 10.1.1.100"
        ];

    networking.firewall.allowedUDPPorts = lib.mkOptionDefault [ 53 ];
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ 53 ];
  };
}

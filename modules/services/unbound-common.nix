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
      lib.concatMapStrings (record: "local-data: \"${record}\"\n") (
        lib.mapAttrsToList (name: host:
          "${name}.lan. IN A ${host.ip}"
        ) config.networking.cluster.hosts ++ [
          # Tailscale mobile device
          "seeker.lan. IN A 100.84.24.43"

          # Service DNS — VIP for HA (requires keepalived active)
          "search.lan. IN A ${config.networking.cluster.kubernetes.vip}"
          "ai.lan. IN A ${config.networking.cluster.kubernetes.vip}"
          "openwebui.lan. IN A ${config.networking.cluster.kubernetes.vip}"
          "haven.lan. IN A ${config.networking.cluster.kubernetes.vip}"
          "hermes.lan. IN A ${config.networking.cluster.kubernetes.vip}"
          "api.hermes.lan. IN A ${config.networking.cluster.kubernetes.vip}"
          "n8n.lan. IN A ${config.networking.cluster.kubernetes.vip}"
          "searxng.lan. IN A ${config.networking.cluster.kubernetes.vip}"
          "activepieces.lan. IN A ${config.networking.cluster.kubernetes.vip}"
        ]);

    networking.firewall.allowedUDPPorts = lib.mkOptionDefault [ 53 ];
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ 53 ];

    networking.firewall.extraInputRules = lib.mkAfter ''
      ip saddr { 10.1.1.0/24, 10.244.0.0/16 } udp dport 53 accept
      ip saddr { 10.1.1.0/24, 10.244.0.0/16 } tcp dport 53 accept
    '';
  };
}

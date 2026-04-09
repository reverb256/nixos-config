# HAProxy Ingress Load Balancer
# Forwards VIP:80/443 to Caddy ingress nodes (nexus, forge, sentry)
#
# Usage:
#   services.haproxy-ingress = {
#     enable = true;
#     vip = "10.1.1.100";
#   };
#
{
  config,
  lib,
  ...
}:
let
  cfg = config.services.haproxy-ingress;
  caddyBackends = "nexus forge sentry";
in
{
  options.services.haproxy-ingress = {
    enable = lib.mkEnableOption "HAProxy ingress load balancer";
    vip = lib.mkOption {
      type = lib.types.str;
      default = "10.1.1.100";
      description = "Virtual IP to listen on";
    };
  };

  config = lib.mkIf cfg.enable {
    services.haproxy = {
      enable = true;
      config = ''
        defaults
          mode tcp
          timeout connect 5s
          timeout client 30s
          timeout server 30s
          option tcplog

        # HTTP frontend
        frontend http-in
          bind ${cfg.vip}:80
          default_backend caddy-http

        # HTTPS frontend
        frontend https-in
          bind ${cfg.vip}:443
          default_backend caddy-https

        # Caddy HTTP backends
        backend caddy-http
          balance roundrobin
          option httpchk GET / HTTP/1.1\r\nHost:\ health.local
          server nexus 10.1.1.120:80 check
          server forge 10.1.1.130:80 check
          server sentry 10.1.1.140:80 check

        # Caddy HTTPS backends
        backend caddy-https
          balance roundrobin
          server nexus 10.1.1.120:443 check ssl verify none
          server forge 10.1.1.130:443 check ssl verify none
          server sentry 10.1.1.140:443 check ssl verify none
      '';
    };

    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [
      80
      443
    ];
  };
}

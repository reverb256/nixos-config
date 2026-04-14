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

        frontend http-in
          bind ${cfg.vip}:80
          default_backend caddy-http

        frontend https-in
          bind ${cfg.vip}:443
          default_backend caddy-https

        backend caddy-http
          balance roundrobin
          option httpchk GET / HTTP/1.1\r\nHost:\ health.local
          server nexus 10.1.1.120:80 check
          server forge 10.1.1.130:80 check
          server sentry 10.1.1.140:80 check

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

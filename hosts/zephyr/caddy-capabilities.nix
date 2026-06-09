{
  config,
  lib,
  ...
}: {
  # Caddy needs CAP_NET_BIND_SERVICE to bind to ports 80/443 as non-root user
  systemd.services.caddy = lib.mkIf (config.services.caddy.enable or false) {
    serviceConfig = {
      AmbientCapabilities = "CAP_NET_BIND_SERVICE";
      CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";
    };
  };
}

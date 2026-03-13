# Nix Binary Cache Server
# Uses Harmonia (Rust-based) to provide binary cache for cluster nodes
# https://github.com/nix-community/harmonia
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.nix-cache;
in {
  options.services.nix-cache = {
    enable = lib.mkEnableOption "Nix binary cache server (Harmonia)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 5000;
      description = "Port for cache HTTP server";
    };

    storeDir = lib.mkOption {
      type = lib.types.path;
      default = "/nix/store";
      description = "Nix store directory to serve";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Address to listen on";
    };
  };

  config = lib.mkIf cfg.enable {
    # Open firewall for cache access
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [cfg.port];

    # Cache info file
    environment.etc."nix-cache-info".text = ''
      Cache Server: ${config.networking.hostName}.tigris-ule.ts.net
      Port: ${toString cfg.port}
      URL: http://${config.networking.hostName}.tigris-ule.ts.net:${toString cfg.port}
      StoreDir: ${cfg.storeDir}
    '';

    # Harmonia service configuration
    services.harmonia.cache = {
      enable = true;
      settings = {
        bind = "${cfg.listenAddress}:${toString cfg.port}";
        # No signing keys for internal cluster use (trusted)
        # Workers = number of CPU cores for parallel compression
        workers = 24;
        # Priority for this cache (higher = more preferred)
        priority = 40;
      };
    };
  };
}

# Nix Binary Cache Server
# Uses nix-serve to provide binary cache for cluster nodes
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.nix-cache;
in {
  options.services.nix-cache = {
    enable = lib.mkEnableOption "Nix binary cache server (nix-serve)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 50000;
      description = "Port for cache HTTP server";
    };

    storeDir = lib.mkOption {
      type = lib.types.path;
      default = "/nix/store";
      description = "Nix store directory to serve";
    };
  };

  config = lib.mkIf cfg.enable {
    # Open firewall for cache access
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [cfg.port];

    # nix-serve service (built-in to Nix)
    systemd.services.nix-serve = {
      description = "Nix binary cache server";
      after = ["network-online.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "notify";
        NotifyAccess = "all";
        ExecStart = "${pkgs.nix}/bin/nix-serve --listen ${cfg.port} --write";
        Restart = "on-failure";
      };

      # Cache configuration
      environment.etc."nix-cache-info".text = ''
        Cache Server: ${config.networking.hostName}.${config.networking.domain}
        Port: ${toString cfg.port}
        URL: http://${config.networking.fqdn}:${toString cfg.port}
      '';
    };
  };
}

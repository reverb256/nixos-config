# Unified Unbound DNS Configuration for All Cluster Hosts
# Simple configuration using standard NixOS unbound module
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkIf mkOption types;
  cfg = config.clusterNetworking;
in {
  options.services.unbound-common = {
    enable = lib.mkEnableOption "Unbound DNS resolver with DNS-over-TLS (cluster-wide config)";
  };

  config = mkIf cfg.enable {
    services.unbound = {
      enable = true;

      settings = {
        server = {
          interface = [ "127.0.0.1" cfg.ipAddress ];
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
        };

        forward-zone = [{
          name = ".";
          forward-addr = [ "1.1.1.1" "1.0.0.1" "8.8.8.8" "8.8.4.4" ];
        }];
      };
    };

    networking.firewall.allowedUDPPorts = lib.mkOptionDefault [ 53 ];
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ 53 ];
  };
}

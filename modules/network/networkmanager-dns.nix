# NetworkManager DNS Configuration Module
# Configures NetworkManager to use local unbound DNS and sets interface priorities
{ config
, lib
, pkgs
, ...
}: let
  cfg = config.networking.networkmanager-dns;
  inherit
    (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
in {
  options.networking.networkmanager-dns = {
    enable = mkEnableOption "Configure NetworkManager DNS settings";

    dnsServers = mkOption {
      type = types.listOf types.str;
      default = [ "127.0.0.1" ];
      description = "DNS servers to use (default: local unbound)";
    };

    ethernetMetric = mkOption {
      type = types.int;
      default = 50;
      description = "Route metric for ethernet (lower = higher priority)";
    };

    wifiMetric = mkOption {
      type = types.int;
      default = 100;
      description = "Route metric for WiFi (lower = higher priority)";
    };
  };

  config = mkIf cfg.enable {
    # Configure NetworkManager DNS
    networking.networkmanager = {
      # Ensure DNS doesn't get overridden by DHCP
      dns = "default";
    };

  };
}

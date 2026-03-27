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
    # Configure NetworkManager via global configuration
    networking.networkmanager = {
      # Set default DNS servers for all connections
      extraConfig = ''
        [global-dns]
        searches=none
        ${lib.concatMapStringsSep "\n" (server: "servers=${server}") cfg.dnsServers}

        [connection]
        ethernet.metric=${toString cfg.ethernetMetric}
        wifi.metric=${toString cfg.wifiMetric}
      '';

      # Ensure DNS doesn't get overridden by DHCP
      dns = "default";
    };

    # Create NetworkManager dispatcher script to ensure DNS is set correctly
    environment.etc."NetworkManager/dispatcher.d/10-dns-servers".text = ''
      #!/bin/sh
      # Set DNS servers to local unbound
      interface=$1
      status=$2

      case "$status" in
        up|dhcp4-change|dhcp6-change)
          # Set DNS via nmcli (more reliable than resolvconf)
          for server in ${lib.concatStringsSep " " cfg.dnsServers}; do
            nmcli connection modify "$interface" ipv4.dns "$server" 2>/dev/null || true
            nmcli connection modify "$interface" ipv6.dns "$server" 2>/dev/null || true
          done
          ;;
      esac
    '';

    # Make dispatcher script executable
    systemd.tmpfiles.rules = [
      "Z /etc/NetworkManager/dispatcher.d/10-dns-servers - - - -"
    ];
  };
}

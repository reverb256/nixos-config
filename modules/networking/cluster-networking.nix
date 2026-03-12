# Cluster Networking Module
# Centralized networking configuration for all cluster nodes
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkOption types mkIf mkMerge;
  cfg = config.clusterNetworking;
in {
  options.clusterNetworking = {
    enable = mkEnableOption "Cluster networking configuration";

    # Node-specific identity
    hostName = mkOption {
      type = types.str;
      description = "Hostname for this node";
    };

    ipAddress = mkOption {
      type = types.str;
      example = "10.1.1.110";
      description = "Static IPv4 address for this node";
    };

    interfaceName = mkOption {
      type = types.str;
      example = "enp38s0";
      description = "Network interface name for wired connection";
    };

    # Optional WiFi configuration
    wireless = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable wireless networking";
      };
    };

    # Unbound DNS resolver configuration
    unbound = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable local Unbound DNS resolver";
      };

      listenAddress = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "IP address for Unbound to listen on (in addition to localhost)";
      };
    };
  };

  config = mkIf cfg.enable {
    # ============================================================================
    # NETWORKING CONFIGURATION
    # ============================================================================
    networking = {
      # Host identity
      inherit (cfg) hostName;

      # DNS search domains for cluster
      search = ["lan" "cluster.local" "tigris-ule.ts.net"];

      # NetworkManager for flexible network configuration
      networkmanager = {
        enable = true;
        dns = "none";  # Use Unbound, not NetworkManager's DNS

        # Wired connection profile
        ensureProfiles.profiles."Wired connection 1" = {
          connection = {
            id = "Wired connection 1";
            type = "ethernet";
            interface-name = cfg.interfaceName;
            autoconnect = true;
          };
          ipv4 = {
            method = "manual";
            address1 = "${cfg.ipAddress}/24";
            gateway = "10.1.1.1";  # Modem/gateway
            dns = "127.0.0.1,::1";  # Use local Unbound resolver
          };
          ipv6.method = "auto";
        };
      };

      # WiFi configuration (optional)
      wireless.enable = cfg.wireless.enable;
    };

    # ============================================================================
    # DNS RESOLVER
    # ============================================================================
    services.unbound-cluster = {
      enable = cfg.unbound.enable;
      listenAddress = cfg.unbound.listenAddress;
    };

    # ============================================================================
    # FIREWALL (Base cluster defaults)
    # ============================================================================
    # Uses mkOptionDefault so nodes can extend these without replacing them
    networking.firewall = {
      enable = true;
      allowedTCPPorts = lib.mkOptionDefault [
        53    # DNS (Unbound)
        22    # SSH
        6443  # Kubernetes API
      ];
      allowedUDPPorts = lib.mkOptionDefault [
        53     # DNS (Unbound)
        41641  # Tailscale coordination server
      ];
    };

    # ============================================================================
    # RELATED SERVICES
    # ============================================================================
    # Tailscale VPN for secure remote access
    services.tailscale.enable = true;

    # Enable mDNS for local service discovery
    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
      };
    };
  };
}

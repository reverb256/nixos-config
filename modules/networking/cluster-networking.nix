# Cluster Networking Module
# Centralized networking configuration for all cluster nodes
{
  config,
  lib,
  ...
}: let
  inherit (lib) mkEnableOption mkOption types mkIf;
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

      # Use systemd-networkd for wired (primary connection)
      useNetworkd = true;

      # Static IP for wired interface (managed by systemd-networkd)
      interfaces.${cfg.interfaceName}.ipv4.addresses = [{
        address = cfg.ipAddress;
        prefixLength = 24;
      }];

      # Default route via gateway
      defaultGateway = "10.1.1.1";
      defaultGateway6 = { address = "fe80::1"; interface = cfg.interfaceName; };

      # NetworkManager for WiFi backup only (not wired)
      networkmanager = {
        enable = cfg.wireless.enable;
        dns = "none"; # Use Unbound, not NetworkManager's DNS
        wifi.backend = "wpa_supplicant"; # Use wpa_supplicant for WiFi
        # Note: No ensureProfiles for wired - systemd-networkd handles that
        # WiFi profiles are managed interactively via nmcli/nmtui
      };

      # Enable wpa_supplicant for WiFi (only when NetworkManager is enabled)
      wireless.enable = cfg.wireless.enable;
    };

    # ============================================================================
    # SERVICES - DNS, VPN, and Service Discovery
    # ============================================================================
    services = {
      unbound-cluster = {
        enable = cfg.unbound.enable;
        listenAddress = cfg.unbound.listenAddress;
      };

      # Tailscale VPN for secure remote access
      tailscale.enable = true;

      # Enable mDNS for local service discovery
      avahi = {
        enable = true;
        nssmdns4 = true;
        publish = {
          enable = true;
          addresses = true;
          workstation = true;
        };
      };
    };

    # ============================================================================
    # FIREWALL (Base cluster defaults)
    # ============================================================================
    # Uses mkOptionDefault so nodes can extend these without replacing them
    networking.firewall = {
      enable = true;
      allowedTCPPorts = lib.mkOptionDefault [
        53 # DNS (Unbound)
        22 # SSH
        6443 # Kubernetes API
      ];
      allowedUDPPorts = lib.mkOptionDefault [
        53 # DNS (Unbound)
        41641 # Tailscale coordination server
      ];
    };
  };
}

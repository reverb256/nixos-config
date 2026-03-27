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
      description = "Static IPv4 address for wired interface";
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

      ipAddress = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "10.1.1.115";
        description = "Static IPv4 address for WiFi interface (null = DHCP)";
      };
    };

    # USB Ethernet adapter support (MAC-based matching)
    usbEthernet = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable static IP for USB Ethernet adapters";
      };

      macAddresses = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["00:11:22:33:44:55"];
        description = "MAC addresses of USB Ethernet adapters to configure with static IP";
      };

      ipAddress = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "10.1.1.110";
        description = "Static IP for USB Ethernet adapters (same as main IP by default)";
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

      # Disable IPv6 - not used in cluster, reduces attack surface
      enableIPv6 = false;

      # Use systemd-networkd for all interfaces
      useNetworkd = true;

      # Static IP for wired interface
      interfaces.${cfg.interfaceName}.ipv4.addresses = [
        {
          address = cfg.ipAddress;
          prefixLength = 24;
        }
      ];

      # Static IP for WiFi interface (if configured)
      interfaces."wlo1" = lib.mkIf (cfg.wireless.enable && cfg.wireless.ipAddress != null) {
        ipv4.addresses = [
          {
            address = cfg.wireless.ipAddress;
            prefixLength = 24;
          }
        ];
      };

      # Default route via gateway
      defaultGateway = {
        address = "10.1.1.1";
        interface = cfg.interfaceName;
      };

      # NetworkManager disabled - use systemd-networkd for everything
      networkmanager.enable = false;

      # Disable wpa_supplicant
      wireless.enable = false;
    };

    # ============================================================================
    # SYSTEMD-NETWORKD CONFIGURATION
    # ============================================================================
    systemd.network.networks = {
      # WiFi interface with static IP (low priority = high metric)
      "10-wifi" = lib.mkIf (cfg.wireless.enable && cfg.wireless.ipAddress != null) {
        matchConfig.Name = "wlo1";
        networkConfig = {
          DHCP = "no";
          DNS = ["127.0.0.1" "::1"];
        };
        address = [
          "${cfg.wireless.ipAddress}/24"
        ];
        routes = [
          { Gateway = "10.1.1.1"; Metric = 600; }
        ];
      };

      # USB Ethernet adapters (driver-based matching for plug/unplug support)
      # Matches any USB ethernet adapter using Type=ether + Driver pattern
      "20-usb-ethernet" = lib.mkIf cfg.usbEthernet.enable {
        matchConfig = {
          Kind = "ether";
          # Use Path property for USB devices (alternative to Driver matching)
          # USB devices have ID_PATH containing "usb"
        };
        networkConfig = {
          DHCP = "no";
          DNS = ["127.0.0.1" "::1"];
        };
        address = [
          "${if cfg.usbEthernet.ipAddress != null then cfg.usbEthernet.ipAddress else cfg.ipAddress}/24"
        ];
        routes = [
          { Gateway = "10.1.1.1"; Metric = 200; }
        ];
      };
    };

    # ============================================================================
    # SERVICES - DNS, VPN, and Service Discovery
    # ============================================================================
    services = {
      unbound-cluster = {
        inherit (cfg.unbound) enable;
        inherit (cfg.unbound) listenAddress;
      };

      # Configure Unbound to listen on VIP for CoreDNS forwarding
      unbound.settings.server.interface = [ "127.0.0.1" cfg.unbound.listenAddress "10.1.1.100" ];

      # Allow Kubernetes pod network to query Unbound for external DNS
      unbound.settings.server.access-control = [
        "127.0.0.0/8 allow"
        "10.1.1.0/24 allow"
        "10.244.0.0/16 allow"
        "100.64.0.0/10 allow"
      ];



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
      # Base ports - K8s API (6443) restricted to Tailscale only (see below)
      allowedTCPPorts = lib.mkOptionDefault [
        53 # DNS (Unbound)
        22 # SSH
      ];
      allowedUDPPorts = lib.mkOptionDefault [
        53 # DNS (Unbound)
        41641 # Tailscale coordination server
      ];
      # Allow Kubernetes pod network to reach Unbound DNS
      extraCommands = ''
        iptables -A nixos-fw -s 10.244.0.0/16 -p udp --dport 53 -j nixos-fw-accept
        iptables -A nixos-fw -s 10.244.0.0/16 -p tcp --dport 53 -j nixos-fw-accept
      '';
      # SECURITY: Kubernetes API accessible via Tailscale VPN only
      # This reduces exposure to local network and provides encrypted access
      interfaces."tailscale0".allowedTCPPorts = [6443];
    };
  };
}

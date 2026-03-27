# Cluster Networking Module
# Centralized networking configuration for all cluster nodes
{
  config,
  lib,
  pkgs,
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

      # Use NetworkManager for all interfaces (not systemd-networkd)
      useNetworkd = false;
      networkmanager.enable = true;

      # Don't use static interface configuration - let NetworkManager handle it
      # via connection profiles in /etc/NetworkManager/system-connections/
    };

    # ============================================================================
    # NETWORKMANAGER CONNECTION PROFILES
    # ============================================================================
    # NetworkManager will manage all connections with static IPs
    environment.etc."NetworkManager/system-connections".source = pkgs.runCommand "nm-connections" { } ''
        # Create directory structure for NetworkManager connections
        mkdir -p $out
        cd $out

        # Wired Ethernet connection (primary, low metric = high priority)
        cat > wired.nmconnection <<EOF
        [connection]
        id=wired
        type=ethernet
        interface-name=${cfg.interfaceName}
        autoconnect=true

        [ipv4]
        method=manual
        address1=${cfg.ipAddress}/24,10.1.1.1
        route-metric=50

        [ipv6]
        method=disabled
        EOF
      '' + lib.optionalString (cfg.wireless.enable) ''
        # WiFi connection (if enabled, higher metric = lower priority)
        cat > wifi.nmconnection <<EOF
        [connection]
        id=wifi
        type=wifi
        interface-name=wlo1
        autoconnect=true

        [wifi]
        ssid=Tigris-Guest
        mode=infrastructure

        [ipv4]
        ${if cfg.wireless.ipAddress != null then "method=manual\naddress1=${cfg.wireless.ipAddress}/24,10.1.1.1" else "method=dhcp"}
        route-metric=100

        [ipv6]
        method=disabled
        EOF
      '' + lib.optionalString cfg.usbEthernet.enable ''
        # USB Ethernet connections (if enabled, very low priority)
        cat > usb-ethernet.nmconnection <<EOF
        [connection]
        id=usb-ethernet
        type=ethernet
        autoconnect=true

        [ipv4]
        method=manual
        address1=${if cfg.usbEthernet.ipAddress != null then cfg.usbEthernet.ipAddress else cfg.ipAddress}/24,10.1.1.1
        route-metric=200

        [ipv6]
        method=disabled
        EOF
      '';

    # ============================================================================
    # SYSTEMD-NETWORKD CONFIGURATION (DISABLED - using NetworkManager instead)
    # ============================================================================
    # systemd.network.networks = { ... };  # Removed - using NetworkManager
    systemd.network.links = {
      # Disable interface renaming - keep kernel names (enp*, wlp*, enx*)
      "10-keep-names" = {
        matchConfig = { OriginalName = "*"; };
        linkConfig = {
          NamePolicy = "keep";
        };
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

      # Configure Unbound to listen on localhost and VIP for CoreDNS forwarding
      unbound.settings.server.interface = [ "127.0.0.1" "::1" cfg.unbound.listenAddress "10.1.1.100" ];

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
    # NETWORKMANAGER DNS CONFIGURATION
    # ============================================================================
    networking.networkmanager.dns = "default";  # Don't override with DHCP
    # DNS servers will be configured via NetworkManager connection profiles

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

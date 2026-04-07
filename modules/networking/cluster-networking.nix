# Cluster Networking Module
# Centralized networking configuration for all cluster nodes
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
  cfg = config.clusterNetworking;
in
{
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
        default = [ ];
        example = [ "00:11:22:33:44:55" ];
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
      search = [
        "lan"
        "cluster.local"
        "tigris-ule.ts.net"
      ];

      # Disable IPv6 - not used in cluster, reduces attack surface
      enableIPv6 = false;

      # Use NetworkManager for all interfaces (not systemd-networkd)
      useNetworkd = false;
      networkmanager.enable = true;

      # Don't use static interface configuration - let NetworkManager handle it
      # via connection profiles in /etc/NetworkManager/system-connections/
    };

    # NOTE: NetworkManager connection profiles managed directly by NM
    # (via nmcli or /etc/NetworkManager/system-connections/*.nmconnection files)
    # Do NOT use environment.etc."system-connections" — it creates a symlink that
    # conflicts with user-created .nmconnection files and breaks on every switch.

    # ============================================================================
    # SYSTEMD-NETWORKD CONFIGURATION (DISABLED - using NetworkManager instead)
    # ============================================================================
    # systemd.network.networks = { ... };  # Removed - using NetworkManager
    systemd.network.links = {
      # Disable interface renaming - keep kernel names (enp*, wlp*, enx*)
      "10-keep-names" = {
        matchConfig = {
          OriginalName = "*";
        };
        linkConfig = {
          NamePolicy = "keep";
        };
      };
    };

    # ============================================================================
    # SERVICES - DNS, VPN, and Service Discovery
    # ============================================================================
    services = {
      # NOTE: Unbound configuration moved to hosts/zephyr/configuration.nix (2026-03-27)
      # DNS-over-TLS to Cloudflare, Google, Quad9 configured per-host
      # Kubernetes DNS forwarding handled in host config

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
    networking.networkmanager.dns = "default"; # Don't override with DHCP
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
        10250 # Kubelet API (required for kubectl exec/logs, Calico health checks)
        6443 # Kubernetes API server (CRITICAL: Must be accessible via LAN for cluster communication)
        9100 # Prometheus node-exporter (all cluster hosts)
      ];
      allowedUDPPorts = lib.mkOptionDefault [
        53 # DNS (Unbound)
        41641 # Tailscale coordination server
      ];
      # Allow Kubernetes pod network to reach Unbound DNS (nftables syntax)
      extraInputRules = ''
        ip saddr 10.244.0.0/16 udp dport 53 accept
        ip saddr 10.244.0.0/16 tcp dport 53 accept
      '';
      # SECURITY: Kubernetes API accessible via Tailscale VPN only
      # Note: cluster-firewall.nix also allows 6443 from cluster LAN
      interfaces."tailscale0".allowedTCPPorts = [ 6443 ];
    };
  };
}

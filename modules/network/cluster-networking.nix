{
  config,
  lib,
  pkgs,
  ...
}: let
  cluster = config.networking.cluster;
  inherit
    (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    mkDefault
    ;
  cfg = config.clusterNetworking;
in {
  options.clusterNetworking = {
    enable = mkEnableOption "Cluster networking configuration";

    hostName = mkOption {
      type = types.str;
      description = "Hostname for this node";
    };

    ipAddress = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = cluster.hosts.zephyr.ip;
      description = "Static IPv4 address for wired interface (null = not a cluster node)";
    };

    interfaceName = mkOption {
      type = types.str;
      example = "enp38s0";
      description = "Network interface name for wired connection";
    };

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
        example = cluster.hosts.zephyr.ip;
        description = "Static IP for USB Ethernet adapters (same as main IP by default)";
      };
    };

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

    # ── Single source of truth for all .lan service domains ──
    # Populated by cluster-dns.nix, consumed by cluster-ca.nix.
    # Adding a domain here automatically adds it to:
    #   1. Unbound DNS records (via cluster-dns.nix)
    #   2. Leaf certificate SANs (via cluster-ca.nix)
    # Do NOT add domains to cluster-ca.nix directly — add them here.
    lanDomains = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["auth.lan" "maplespike.lan"];
      description = "List of all .lan service domain FQDNs. Single source of truth for DNS + TLS certs.";
    };
  };

  config = mkIf cfg.enable {
    networking = {
      inherit (cfg) hostName;

      search = [
        "lan"
        "cluster.local"
        "taila21e09.ts.net"
      ];

      nameservers = ["127.0.0.1"];
      enableIPv6 = false;

      useNetworkd = false;
      networkmanager.enable = true;
    };

    systemd.network.links = {
      "10-keep-names" = {
        matchConfig = {
          OriginalName = "*";
        };
        linkConfig = {
          NamePolicy = "keep";
        };
      };
    };

    services = {
      tailscale.enable = true;

      # DNS tunnel protection — enabled by default on all cluster nodes

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

    networking.networkmanager.dns = "none";

    networking.firewall = {
      enable = true;
      allowedTCPPorts = lib.mkOptionDefault [
        53
        22
        10250
        6443
        9100
      ];
      allowedUDPPorts = lib.mkOptionDefault [
        53
        41641
      ];
      extraInputRules = ''
        ip saddr 10.42.0.0/16 udp dport 53 accept
        ip saddr 10.42.0.0/16 tcp dport 53 accept
      '';
      interfaces."tailscale0".allowedTCPPorts = [6443];
    };
  };
}
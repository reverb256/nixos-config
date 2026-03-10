# Network Constants Module
# Centralized network configuration for all cluster hosts
# This eliminates hardcoded IPs scattered across host configurations
{lib, ...}: {
  options.networking.cluster = lib.mkOption {
    type = lib.types.attrs;
    default = {
      # Cluster network configuration
      subnet = "10.1.1.0/24";
      gateway = "10.1.1.1";
      dns = [
        "127.0.0.1" # Local Unbound resolver (now with proper DoT)
        "::1"
      ];

      # Host definitions with IPs and roles
      # Note: Interfaces are auto-detected by NetworkManager (not hardcoded)
      hosts = {
        zephyr = {
          ip = "10.1.1.110";
          tailscale = "100.81.182.5";
          description = "Master Workstation - 32 cores, RTX 3090";
          roles = [
            "desktop"
            "gaming"
            "vr"
            "mining"
            "build"
            "ai"
          ];
          # Advertises subnet route on Tailscale (gateway for cluster)
          advertiseRoutes = ["10.1.1.0/24"];
        };

        nexus = {
          ip = "10.1.1.120";
          tailscale = "100.86.158.18";
          description = "Build/AIStor Server - 24 cores, 1x RTX 3060 Ti";
          roles = [
            "desktop"
            "gaming"
            "vr"
            "mining"
            "build"
            "storage"
          ];
          # Does not advertise routes (zephyr handles that)
          advertiseRoutes = [];
        };

        forge = {
          ip = "10.1.1.130";
          tailscale = "100.95.222.45";
          description = "GPU Mining - 6 cores, 2x RTX 4060 + 2x RX 5700 XT";
          roles = [
            "mining"
            "build"
          ];
          # Advertises subnet route on Tailscale (backup gateway)
          advertiseRoutes = ["10.1.1.0/24"];
        };

        sentry = {
          ip = "10.1.1.140";
          tailscale = "100.82.210.39";
          description = "Monitoring Server - 16 cores, RX 5600 XT";
          roles = [
            "monitoring"
            "build"
          ];
          # Advertises subnet route on Tailscale (backup gateway)
          advertiseRoutes = ["10.1.1.0/24"];
        };
      };

      # Tailscale network configuration
      tailscale = {
        domain = "tigris-ule.ts.net";
        dnsServer = "100.100.100.100";
      };

      # Common ports used across the cluster
      ports = {
        # WiVRn VR streaming
        wivrn-tcp = 9757;
        wivrn-udp-start = 9757;
        wivrn-udp-end = 9760;

        # MCP/AI services (Tailscale only)
        mcp-api = 18789;
        mcp-storage = 18790;

        # Steam
        steam-tcp = [
          27031
          27036
        ];
        steam-udp = [
          27031
          27036
        ];

        # mDNS
        mdns = 5353;

        # LocalSend
        localsend = 53317;

        # Mining API (localhost only)
        xmrig-api = 8081;
        lolminer-nvidia-api = 4068;
        lolminer-amd-api = 4069;

        # Nix cache
        nix-cache = 8080;

        # Monitoring
        prometheus = 9090;
        alertmanager = 9093;
        grafana = 3001;
        node-exporter = 9100;
        nvidia-exporter = 9400;
      };
    };
    description = "Cluster network configuration constants";
    readOnly = true;
  };

  # Note: Access current host's config directly via config.networking.cluster.hosts.${config.networking.hostName}
  # The currentHost convenience option was removed to prevent infinite recursion
}

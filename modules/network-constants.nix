{lib, ...}: {
  options.networking.cluster = lib.mkOption {
    type = lib.types.attrs;
    default = {
      subnet = "10.1.1.0/24";
      gateway = "10.1.1.1";
      dns = [
        "127.0.0.1"
        "::1"
      ];

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
          advertiseRoutes = ["10.1.1.0/24"];
        };
      };

      tailscale = {
        domain = "tigris-ule.ts.net";
        dnsServer = "100.100.100.100";
      };

      ports = {
        wivrn-tcp = 9757;
        wivrn-udp-start = 9757;
        wivrn-udp-end = 9760;

        mcp-api = 18789;
        mcp-storage = 18790;

        steam-tcp = [
          27031
          27036
        ];
        steam-udp = [
          27031
          27036
        ];

        mdns = 5353;

        localsend = 53317;

        xmrig-api = 8081;
        lolminer-nvidia-api = 4068;
        lolminer-amd-api = 4069;

        nix-cache = 8080;

        prometheus = 9090;
        alertmanager = 9093;
        grafana = 3001;
        node-exporter = 9100;
        nvidia-exporter = 9400;

        caddy-admin = 2019;
        caddy-http = 80;
        caddy-https = 443;
        caddy-nodeport-http = 30080;
        caddy-nodeport-https = 30443;
      };

      kubernetes = {
        vip = "10.1.1.100";
        apiPort = 6443;
      };
    };
    description = "Cluster network configuration constants";
    readOnly = true;
  };

}

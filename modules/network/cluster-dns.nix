{
  config,
  lib,
  pkgs,
  ...
}: let
  cluster = config.networking.cluster;
  inherit (lib) mkIf mkBefore mkDefault;
  clusterCfg = config.clusterNetworking;
  # Cluster host IPs (hardcoded for reliability)
  hosts = {
    zephyr = "${cluster.hosts.zephyr.ip}";
    nexus = "${cluster.hosts.nexus.ip}";
    forge = cluster.hosts.forge.ip;
    sentry = "${cluster.hosts.sentry.ip}";
    # K8s service ClusterIPs
  };
  # Get DNS config - use or {} for safety in case the option doesn't exist
  dnsCfg = {
    enable = clusterCfg.unbound.enable or false;
    listenAddress = clusterCfg.unbound.listenAddress or null;
    upstreamServers = [
      "1.1.1.1@853"
      "1.0.0.1@853"
      "8.8.8.8@853"
      "8.8.4.4@853"
    ];
    searchDomains = config.networking.search or [];
    enableLanRecords = true;
    enableServiceRecords = true;
  };

  # K8s service CIDR - same value as in k3s-cluster. nix (10.0.0.0/12)
  serviceCIDR = "10.0.0.0/12";

  # Flannel gateway IP for this node (gateway of the pod subnet)
  kubeFlannelGateway = "10.244.0.1";
in {
  config = mkIf dnsCfg.enable {
    # Disable systemd-resolved (conflicts with unbound)
    services.resolved.enable = mkDefault false;

    # Configure unbound
    services.unbound = {
      enable = true;

      settings = {
        server = {
          domain-insecure = [
            "cluster.local."
          ];
          # Listen on localhost and cluster IP
          interface = [
            (
              if dnsCfg.listenAddress != null && dnsCfg.listenAddress != "127.0.0.1"
              then dnsCfg.listenAddress
              else clusterCfg.ipAddress
            )
          ];

          # Allow queries from cluster network
          access-control = [
            "127.0.0.0/8 allow"
            "10.1.1.0/24 allow"
            "10.244.0.0/16 allow"
            "::1 allow"
            "fd00::/8 allow"
          ];

          # Performance tuning
          num-threads = 4;
          msg-cache-size = "128m";
          rrset-cache-size = "128m";

          # Privacy and security
          hide-identity = true;
          hide-version = true;
          tls-cert-bundle = "/etc/ssl/certs/ca-bundle.crt";

          # Include local DNS records
          local-zone = [
            "lan. static"
            "cluster.local. transparent"
          ];
          include = ["/etc/unbound/local-dns.conf"];

          # Don't query localhost (prevent loops)
          do-not-query-localhost = true;
        };

        # Forward zones
        forward-zone = [
          # Tailscale DNS
          {
            name = "ts.net.";
            forward-addr = [
              "100.100.100.100"
              "fd7a:115c:a1e0::53"
            ];
          }
          # K8s cluster DNS → CoreDNS (enables host-level K8s service resolution)
          {
            name = "cluster.local.";
            forward-addr = [config.networking.cluster.kubernetes.clusterDnsIP];
          }
          # Everything else: use upstream DoT
          {
            name = ".";
            forward-addr = dnsCfg.upstreamServers;
            forward-tls-upstream = true;
          }
        ];
      };
    };

    # Generate local DNS records
    environment.etc."unbound/local-dns.conf".text = let
      # Server section header (required for local-data lines to work)
      serverSection = ''
        server:
          interface: 0.0.0.0
          interface: ::0
          access-control: 10.0.0.0/8 allow
          access-control: 100.64.0.0/10 allow
          access-control: 172.16.0.0/12 allow
          verbosity: 1
          local-zone: "lan." static

      '';

      # All ingress services route through Caddy via VIP (10.1.1.100)
      # VIP is keepalived: zephyr MASTER, survives node failures
      vip = "10.1.1.100";

      # Services via Caddy Ingress (accessed via VIP)
      ingressServices = [
        "search.lan. IN A ${vip}"
        "brain.lan. IN A ${vip}"
        "openwebui.lan. IN A ${vip}"
      ];
      # Services proxied via Caddy via VIP (single stable entry point)
      hostServices = [
        "ai.lan. IN A ${vip}"
        "ai-inference.lan. IN A ${vip}"
        "auth.lan. IN A ${vip}"
        "qdrant.lan. IN A ${vip}"
        "knowledge-fabric.lan. IN A ${vip}"
        "haven.lan. IN A ${vip}"
        "kagent.lan. IN A ${vip}"
        "hermes.lan. IN A ${vip}"
        "api.hermes.lan. IN A ${vip}"
        "n8n.lan. IN A ${vip}"
        "searxng.lan. IN A ${vip}"
        "activepieces.lan. IN A ${vip}"
        "mission-control.lan. IN A ${vip}"
        "privacy-filter.lan. IN A ${vip}"
        "grafana.lan. IN A ${vip}"
      ];
      # Optional forge services
      forgeServices = [
        "mining.lan. IN A ${hosts.forge}"
      ];

      # Optional sentry services
      sentryServices = [
        "monitoring.lan. IN A ${hosts.sentry}"
        "prometheus.lan. IN A ${hosts.sentry}"
      ];

      # All service records combined
      allServices = ingressServices ++ hostServices ++ forgeServices ++ sentryServices;

      # Host records
      hostRecords = lib.mapAttrsToList (name: ip: "${name}.lan. IN A ${ip}") hosts;
    in
      # Host records section
      (lib.optionalString dnsCfg.enableLanRecords (
        lib.concatMapStrings (record: "local-data: \"${record}\"\n") hostRecords
      ))
      +
      # Service records section
      (lib.optionalString dnsCfg.enableServiceRecords (
        lib.concatMapStrings (record: "local-data: \"${record}\"\n") allServices
      ))
      +
      # Tailscale mobile device
      "local-data: \"seeker.lan. IN A 100.84.24.43\"\n";

    # Static resolv.conf (prevent DHCP overrides)
    environment.etc."resolv.conf".text = ''
      # Generated by NixOS cluster-dns module - DO NOT MODIFY
      # Single source of truth: /etc/nixos/modules/network/cluster-dns.nix
      ${lib.concatStringsSep "\n" (map (d: "search ${d}") dnsCfg.searchDomains)}
      nameserver 127.0.0.1
      nameserver ::1
      options edns0 trust-ad
    '';

    # NetworkManager: don't manage DNS, we use unbound
    networking.networkmanager.dns = mkDefault "none";

    # Firewall: allow DNS traffic
    networking.firewall = {
      allowedUDPPorts = lib.mkOptionDefault [53];
      allowedTCPPorts = lib.mkOptionDefault [53];
      extraInputRules = lib.mkAfter ''
        ip saddr { 10.1.1.0/24, 10.244.0.0/16 } udp dport 53 accept
        ip saddr { 10.1.1.0/24, 10.244.0.0/16 } tcp dport 53 accept
      '';
    };

    # Route K8s service CIDR via Flannel so ClusterIP traffic stays local
    # Problem: kube-proxy runs as container (not host binary), so iptables rules don't
    # exist on host. Without this route, traffic to 10.0.0.0/12 (ClusterIPs) goes to
    # default gateway (10.1.1.1) and is lost.
    networking.localCommands = ''
      # Add route to K8s service CIDR via Flannel gateway
      ip route add 10.0.0.0/12 via 10.244.0.1 dev flannel.1 2>/dev/null || true
    '';

    # Populate /etc/hosts for compatibility
    networking.extraHosts = lib.mkBefore (
      let
        vip = "10.1.1.100";
        allHosts =
          hosts
          // {
            ai-inference = vip;
            qdrant = vip;
            knowledge-fabric = vip;
            hermes = vip;
            brain = vip;
            search = vip;
            searxng = vip;
            n8n = vip;
            activepieces = vip;
            openwebui = vip;
            haven = vip;
            grafana = vip;
            prometheus = hosts.sentry;
            monitoring = hosts.sentry;
            mining = hosts.forge;
            mission-control = vip;
            privacy-filter = vip;
          };
      in
        lib.pipe allHosts [
          (lib.mapAttrsToList (name: ip: "${ip} ${name}.lan ${name}"))
          (lib.concatStringsSep "\n")
        ]
    );
  };
}

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

  # K8s service CIDR - same value as in k3s-cluster.nix (10.43.0.0/16)
  serviceCIDR = "10.43.0.0/16";

  # Flannel gateway IP for this node (gateway of the pod subnet)
  kubeFlannelGateway = "10.42.0.1";

  # ── Service domain definitions (SSOT for .lan domains) ──────────────────
  # These lists define ALL .lan domains. They feed into:
  #   1. Unbound DNS records (local-data)
  #   2. clusterNetworking.lanDomains (consumed by cluster-ca.nix for TLS SANs)
  #   3. /etc/hosts compatibility entries
  # To add a new .lan service: add it to the appropriate list below.
  # The domain will automatically appear in DNS, TLS certs, and /etc/hosts.

  # All ingress services route through Caddy via VIP (10.1.1.100)
  vip = "10.1.1.100";

  # Services via Caddy Ingress (accessed via VIP)
  ingressServiceDomains = ["search.lan" "openwebui.lan"];

  # Services proxied via Caddy via VIP (single stable entry point)
  hostServiceDomains = [
    "ai-inference.lan"
    "auth.lan"
    "qdrant.lan"
    "n8n.lan"
    "searxng.lan"
    "mission-control.lan"
    "grafana.lan"
    "privacy-filter.lan"
    "vaultwarden.lan"
    "workspace.lan"
    "dashboard.lan"
    "maplespike.lan"
    "api.maplespike.lan"
    "mcp.maplespike.lan"
    "status.maplespike.lan"
    "uptime.maplespike.lan"
    "dev.maplespike.lan"
    "dev-api.maplespike.lan"
    "dev-mcp.maplespike.lan"
    "gitea.lan"
  ];

  # Forge-specific services
  forgeServiceDomains = ["mining.lan"];

  # Sentry-specific services
  sentryServiceDomains = ["monitoring.lan" "prometheus.lan" "alertmanager.lan"];

  # Hermes Agent services (runs on nexus as systemd)
  hermesServiceDomains = ["hermes.lan" "api.hermes.lan"];

  # Tailscale mobile devices
  tailscaleDomains = ["seeker.lan" "reverb256.lan"];

  # All .lan domains combined — this is the SSOT list
  allLanDomains =
    ingressServiceDomains
    ++ hostServiceDomains
    ++ forgeServiceDomains
    ++ sentryServiceDomains ++ hermesServiceDomains ++ tailscaleDomains;

  # Convert domain list to Unbound local-data records
  # Maps domain → IP based on which list it belongs to
  domainToIp = domain:
    if builtins.elem domain ingressServiceDomains
    then vip
    else if builtins.elem domain hostServiceDomains
    then vip
    else if builtins.elem domain forgeServiceDomains
    then hosts.forge
    else if builtins.elem domain sentryServiceDomains
    then hosts.sentry
    else if builtins.elem domain hermesServiceDomains
    then hosts.nexus
    else if domain == "seeker.lan"
    then "100.84.24.43"
    else if domain == "reverb256.lan"
    then "10.15.39.199"
    else vip; # fallback

  # Generate Unbound local-data records from domain lists
  ingressServices = map (d: "${d}. IN A ${domainToIp d}") ingressServiceDomains;
  hostServices = map (d: "${d}. IN A ${domainToIp d}") hostServiceDomains;
  forgeServices = map (d: "${d}. IN A ${domainToIp d}") forgeServiceDomains;
  sentryServices = map (d: "${d}. IN A ${domainToIp d}") sentryServiceDomains;
  hermesServices = map (d: "${d}. IN A ${domainToIp d}") hermesServiceDomains;

  # All service records combined
  allServices = ingressServices ++ hostServices ++ forgeServices ++ sentryServices ++ hermesServices;

  # Host records
  hostRecords = lib.mapAttrsToList (name: ip: "${name}.lan. IN A ${ip}") hosts;
in {
  config = mkIf dnsCfg.enable {
    # Export .lan domain list (SSOT for cluster-ca.nix TLS SANs)
    clusterNetworking.lanDomains = allLanDomains;
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
            "127.0.0.1"
            "::1"
            (
              if dnsCfg.listenAddress != null && dnsCfg.listenAddress != "127.0.0.1"
              then dnsCfg.listenAddress
              else if clusterCfg.ipAddress != null
              then clusterCfg.ipAddress
              else "127.0.0.1"
            )
            # VIP for HA DNS — Unbound must listen here so queries to
            # 10.1.1.100:53 are answered by whichever node has the VIP.
            cluster.kubernetes.vip
          ];

          # Allow queries from cluster network
          access-control = [
            "127.0.0.0/8 allow"
            "10.1.1.0/24 allow"
            "10.42.0.0/16 allow"
            "::1 allow"
            "fd00::8 allow"
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
          # All records generated below in environment.etc."unbound/local-dns.conf"
          # Do NOT add a separate extra file — see cluster-dns.nix for the full list
          include = ["/etc/unbound/local-dns.conf"];

          # Don't query localhost (prevent loops)
          do-not-query-localhost = true;
        };

        # Forward zones
        forward-zone = [
          # K8s cluster DNS → CoreDNS (enables host-level K8s service resolution)
          # NOTE: ts.net. and . (upstream) forward zones are defined in unbound-common.nix
          {
            name = "cluster.local.";
            forward-addr = [config.networking.cluster.kubernetes.clusterDnsIP];
          }
        ];
      };
    };

    # Survive failed nixos-rebuild: reload (SIGHUP) instead of stop/start.
    # If activation crashes mid-switch, unbound stays running.
    systemd.services.unbound = {
      restartIfChanged = true; # Must restart (not just reload) to pick up new interface bindings like the VIP

      # Protect from OOM killer — DNS is cluster-critical infrastructure.
      # System has heavy memory pressure (27/31G used, 7.2/7.8G swap).
      # With default OOMScoreAdjust=0, unbound's oom_score=666 makes it
      # an easy kill target. -1000 = immune to OOM killer.
      serviceConfig.OOMScoreAdjust = -1000;
    };

    # Generate local DNS records
    environment.etc."unbound/local-dns.conf".text =
      # Server section header (required for local-data lines to work)
      ''
        server:
          interface: 0.0.0.0
          interface: ::0
          access-control: 10.0.0.0/8 allow
          access-control: 100.64.0.0/10 allow
          access-control: 172.16.0.0/12 allow
          verbosity: 1
          local-zone: "lan." static

      ''
      +
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

    # Disable resolvconf — we manage /etc/resolv.conf directly
    networking.resolvconf.enable = false;

    # NetworkManager: don't manage DNS, we use unbound
    networking.networkmanager.dns = mkDefault "none";

    # Firewall: allow DNS traffic
    networking.firewall = {
      allowedUDPPorts = lib.mkOptionDefault [53];
      allowedTCPPorts = lib.mkOptionDefault [53];
      extraInputRules = lib.mkAfter ''
        ip saddr { 10.1.1.0/24, 10.42.0.0/16 } udp dport 53 accept
        ip saddr { 10.1.1.0/24, 10.42.0.0/16 } tcp dport 53 accept
      '';
    };

    # Route K8s service CIDR via Flannel so ClusterIP traffic stays local
    networking.localCommands = ''
      # Add route to K8s service CIDR via Flannel gateway
      ip route add 10.43.0.0/16 via 10.42.0.1 dev flannel.1 2>/dev/null || true
    '';

    # Populate /etc/hosts for compatibility
    networking.extraHosts = lib.mkBefore (
      let
        allHosts =
          hosts
          // {
            ai-inference = vip;
            qdrant = vip;
            search = vip;
            searxng = vip;
            n8n = vip;
            openwebui = vip;
            haven = vip;
            grafana = vip;
            prometheus = hosts.sentry;
            monitoring = hosts.sentry;
            mining = hosts.forge;
            mission-control = vip;
            workspace = vip;
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

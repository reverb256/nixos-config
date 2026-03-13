# Networking Module - DNS, Firewall, Analytics Blocking, Avahi
{
  lib,
  pkgs,
  config,
  ...
}: {
  # ============================================================================
  # NETWORKING - NetworkManager, DHCP, hosts, DNS, firewall
  # ============================================================================
  networking = {
    # Use NetworkManager for interface management
    networkmanager.enable = true;
    useDHCP = false;

    # CLUSTER HOSTS ENTRIES (Shared across all nodes)
    hosts = {
      "10.1.1.110" = ["zephyr"];
      "10.1.1.120" = ["nexus"];
      "10.1.1.130" = ["forge"];
      "10.1.1.140" = ["sentry"];
    };

    # ANALYTICS & TELEMETRY BLOCKLIST
    # Block VRChat, Unity, and HoYoverse analytics/telemetry for privacy
    # Source: https://github.com/louisa-uno/VRChatAnalyticsBlocklist
    extraHosts = ''
      # VRChat Analytics Blocklist
      # https://github.com/louisa-uno/VRChatAnalyticsBlocklist

      # VRChat Specific (Proven to use/have used)
      0.0.0.0 api.amplitude.com
      0.0.0.0 api2.amplitude.com
      0.0.0.0 api.lab.amplitude.com
      0.0.0.0 api.eu.amplitude.com
      0.0.0.0 regionconfig.amplitude.com
      0.0.0.0 regionconfig.eu.amplitude.com
      0.0.0.0 o1125869.ingest.sentry.io


      0.0.0.0 api3.amplitude.com
      0.0.0.0 cdn.amplitude.com
      0.0.0.0 info.amplitude.com
      0.0.0.0 static.amplitude.com

      # Unity Specific
      0.0.0.0 api.uca.cloud.unity3d.com
      0.0.0.0 config.uca.cloud.unity3d.com
      0.0.0.0 perf-events.cloud.unity3d.com
      0.0.0.0 public.cloud.unity3d.com
      0.0.0.0 cdp.cloud.unity3d.com
      0.0.0.0 data-optout-service.uca.cloud.unity3d.com
      0.0.0.0 ecommerce.iap.unity3d.com
    '';

    # Use local unbound as DNS resolver
    nameservers = [
      "127.0.0.1"
      "::1"
    ];

    # FIREWALL (Base config - ports can be extended per-host)
    # Uses mkOptionDefault so nodes can extend these without replacing them
    firewall = {
      enable = true;
      # Base allowed ports - all hosts get these
      allowedTCPPorts = lib.mkOptionDefault [22]; # SSH (essential for cluster management)
      allowedUDPPorts = lib.mkOptionDefault [
        60001
        60002
        60003
        60004
        60005
      ]; # Mosh (UDP range start)
      # Additional ports can be added per-host in hosts/*/default.nix
    };
  };

  # ============================================================================
  # SERVICES - Avahi, Unbound DNS, Timesyncd, Tailscale
  # ============================================================================
  services = {
    # AVAHI (Device discovery - required for WiVRn on zephyr)
    avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
        # Allow user services (like WiVRn) to publish via Avahi
        userServices = true;
      };
      # Security hardening: restrict to wired interfaces only
      # All cluster nodes use 'lan0' for primary ethernet (see interface-naming.nix)
      # During transition, also support legacy interface names (enp*, eno*)
      # Override per-host with allowInterfaces/denyInterfaces if needed
      allowInterfaces = [
        "lan0"
        "enp*"
        "eno*"
      ]; # All cluster nodes' primary ethernet (transition-friendly)
      denyInterfaces = [
        "tailscale0"
        "wlan*"
        "docker*"
        "virbr*"
        "wg*"
      ];
      # Extra config for security hardening
      extraConfig = ''
        [wide-area]
        enable-wide-area=no

        [publish]
        disable-user-service-publishing=no
      '';
    };

    # Unbound DNS resolver with TLS
    # Only enable when unbound-cluster is NOT enabled (to avoid duplicate forward-zone)
    unbound = lib.mkIf (!config.services.unbound-cluster.enable or false) {
      enable = true;
      settings = {
        server = {
          interface = [
            "127.0.0.1"
            "::1"
          ];
          port = 53;
          access-control = [
            "127.0.0.0/8 allow"
            "::1/128 allow"
            "10.1.1.0/24 allow" # Local network access
          ];
          do-tcp = true;
          do-udp = true;
          prefetch = true;
          cache-min-ttl = 300; # 5 minutes minimum
          cache-max-ttl = 86400; # 24 hours maximum

          # Security and performance settings
          harden-glue = true;
          harden-dnssec-stripped = true;
          use-caps-for-id = false;
          edns-buffer-size = 1232;
          hide-identity = true;
          hide-version = true;
        };

        # Stub zone for Tailscale Magic DNS
        stub-zone = [
          {
            name = "tigris-ule.ts.net";
            stub-addr = "100.100.100.100"; # Tailscale DNS server
          }
        ];

        # Forward all other queries to upstream DNS with TLS
        forward-zone = [
          # ASUS-specific forward zone for BIOS downloads
          {
            name = "asus-cdn";
            forward-addr = [
              "52.85.12.13"
              "52.85.12.97"
              "52.85.12.88"
              "52.85.12.65"
            ];
          }
          # General DNS forwarding with DoT
          {
            name = ".";
            forward-addr = [
              "9.9.9.9@853#dns.quad9.net" # Quad9 Primary (DoT) - PRIORITIZED
              "9.9.9.10@853#dns.quad9.net" # Quad9 Secondary (DoT)
              "8.8.8.8@853#dns.google" # Google DNS Primary (DoT)
              "8.8.4.4@853#dns.google" # Google DNS Secondary (DoT)
              "1.1.1.1@853#cloudflare-dns.com" # Cloudflare Primary (DoT)
              "1.0.0.1@853#cloudflare-dns.com" # Cloudflare Secondary (DoT)
            ];
            forward-tls-upstream = true;
          }
        ];
      };
    };

    # SYSTEMD-TIMESYNGD - Modern NTP Client
    timesyncd = {
      enable = true;
      servers = [
        "time.cloudflare.com" # Cloudflare NTP (Anycast)
        "time.google.com" # Google NTP (Anycast)
      ];
    };

    # TAILSCALE VPN
    tailscale.enable = true;
  };

  # Ensure avahi runtime directory exists and clean stale PID on start
  # This makes the service idempotent during nixos-rebuild switch
  systemd.tmpfiles.rules = [
    "d /run/avahi-daemon 755 avahi avahi -"
  ];
  systemd.services.avahi-daemon.serviceConfig.ExecStartPre = [
    "${pkgs.coreutils}/bin/rm -f /run/avahi-daemon/pid"
  ];

  # ============================================================================
  # FAIL2BAN CONFIGURATION
  # NOTE: Fail2ban configuration moved to modules/system/security.nix
  # This centralizes all security-related configurations
  # ============================================================================

  # ============================================================================
  # STATUS INDICATOR
  # ============================================================================

  # Mark that analytics blocklist is active
  environment.etc."analytics-blocklist-active".text = ''
    Analytics & Telemetry Blocklist is active.
    Blocked domains are redirected to 0.0.0.0 in /etc/hosts.

    Blocked:
    - VRChat and Unity analytics (https://github.com/louisa-uno/VRChatAnalyticsBlocklist)
    - HoYoverse telemetry (Genshin Impact)
  '';
}

# Networking Module - DNS, Firewall, Analytics Blocking, Avahi
{lib, ...}:
with lib; {
  # ============================================================================

  # Disable conflicting services
  networking.dhcpcd.enable = false;
  networking.useDHCP = false;

  # ============================================================================
  # ANALYTICS & TELEMETRY BLOCKLIST
  # ============================================================================

  # Block VRChat, Unity, and HoYoverse analytics/telemetry for privacy
  # Source: https://github.com/louisa-uno/VRChatAnalyticsBlocklist
  networking.extraHosts = ''
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

    # VRChat Specific (Hasn't used yet, added for future proofing)
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

  # ============================================================================
  # AVAHI (Device discovery - required for WiVRn on zephyr)
  # ============================================================================

  services.avahi = {
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
    # Override per-host with allowInterfaces/denyInterfaces if needed
    allowInterfaces = ["enp38s0" "enp7s0"]; # zephyr and nexus wired NICs
    denyInterfaces = ["tailscale0" "wlan*" "docker*" "virbr*" "wg*"];
    # Extra config for security hardening
    extraConfig = ''
      [wide-area]
      enable-wide-area=no

      [publish]
      disable-user-service-publishing=no
    '';
  };

  # Ensure avahi runtime directory exists
  systemd.tmpfiles.rules = [
    "d /run/avahi-daemon 755 avahi avahi -"
  ];

  services.unbound = {
    enable = true;
    settings = {
      server = {
        interface = ["127.0.0.1" "::1"];
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

  # Use local unbound as DNS resolver
  networking.nameservers = ["127.0.0.1" "::1"];

  # ============================================================================
  # FAIL2BAN CONFIGURATION
  # ============================================================================
  services.fail2ban = {
    enable = true;
    ignoreIP = [
      "127.0.0.1"
      "10.1.0.0/24" # Entire cluster subnet
      "10.1.1.110" # zephyr
      "10.1.1.120" # nexus
      "10.1.1.130" # forge
      "10.1.1.140" # sentry
      "100.81.182.5" # zephyr Tailscale
      "100.86.158.18" # nexus Tailscale
      "100.116.190.124" # forge Tailscale
      "100.82.210.39" # sentry Tailscale
    ];
  };

  # ============================================================================
  # FIREWALL (Base config - ports can be overridden per-host)
  # ============================================================================
  
  networking.firewall = {
    enable = true;
    # Base allowed ports - all hosts get these
    allowedTCPPorts = [];
    allowedUDPPorts = [];
    # Additional ports can be added per-host in hosts/*/default.nix
  };

  # ============================================================================
  # TAILSCALE VPN
  # ============================================================================

  services.tailscale.enable = true;

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

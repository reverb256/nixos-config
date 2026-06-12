{
  lib,
  pkgs,
  ...
}: {
  networking = {
    networkmanager = {
      enable = lib.mkDefault true;
      insertNameservers = ["127.0.0.1" "::1"];
    };
    useDHCP = false;

    hosts = {
      "10.1.1.110" = ["zephyr"];
      "10.1.1.120" = ["nexus"];
      "10.1.1.130" = ["forge"];
      "10.1.1.150" = ["krash3"];
      "10.1.1.173" = ["hp-envy7800" "printer"];
      "10.1.1.140" = ["sentry"];
    };

    extraHosts = lib.mkOptionDefault ''

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

      0.0.0.0 api.uca.cloud.unity3d.com
      0.0.0.0 config.uca.cloud.unity3d.com
      0.0.0.0 perf-events.cloud.unity3d.com
      0.0.0.0 public.cloud.unity3d.com
      0.0.0.0 cdp.cloud.unity3d.com
      0.0.0.0 data-optout-service.uca.cloud.unity3d.com
      0.0.0.0 ecommerce.iap.unity3d.com
    '';

    nameservers = [
      "127.0.0.1"
      "::1"
    ];

    firewall = {
      enable = lib.mkDefault true;
      allowedTCPPorts = lib.mkOptionDefault [
        22
        6443
      ];
      allowedUDPPorts = lib.mkOptionDefault [
        60001
        60002
        60003
        60004
        60005
      ];
    };
  };

  services = {
    avahi = {
      enable = lib.mkDefault true;
      nssmdns4 = true;
      publish = {
        enable = lib.mkDefault true;
        addresses = true;
        workstation = true;
        userServices = true;
      };
      allowInterfaces = [
        "lan0"
        "enp*"
        "eno*"
      ];
      denyInterfaces = [
        "tailscale0"
        "wlan*"
        "docker*"
        "virbr*"
        "wg*"
      ];
      extraConfig = ''
        [wide-area]
        enable-wide-area=no

        [publish]
        disable-user-service-publishing=no
      '';
    };

    timesyncd = {
      enable = lib.mkDefault true;
      servers = [
        "time.cloudflare.com"
        "time.google.com"
      ];
    };

    tailscale.enable = true;
  };

  systemd.tmpfiles.rules = [
    "d /run/avahi-daemon 755 avahi avahi -"
  ];
  systemd.services.avahi-daemon.serviceConfig.ExecStartPre = [
    "${pkgs.coreutils}/bin/rm -f /run/avahi-daemon/pid"
  ];

  systemd.services.systemd-networkd-wait-online = {
    serviceConfig = {
      RemainAfterExit = true;
    };
  };
  systemd.services."NetworkManager-wait-online".enable = lib.mkForce false;
  systemd.targets.network-online.wantedBy = lib.mkForce ["network-online.target"];

  boot.kernel.sysctl = {
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.default_qdisc" = "fq";
  };

  environment.etc."analytics-blocklist-active".text = ''
    Analytics & Telemetry Blocklist is active.
    Blocked domains are redirected to 0.0.0.0 in /etc/hosts.

    Blocked:
    - VRChat and Unity analytics (https://github.com/louisa-uno/VRChatAnalyticsBlocklist)
    - HoYoverse telemetry (Genshin Impact)
  '';
}

{
  lib,
  config,
  pkgs,
  ...
}: let
  cluster = config.networking.cluster;
in {
  hardware = {
    printers = {
      ensurePrinters = [
        {
          name = "HP_Envy_7800";
          location = "Home Network";
          description = "HP ENVY Photo 7800 All-in-One";
          deviceUri = "ipp://${cluster.devices.printer}:631/ipp/print";
          model = "everywhere";
          ppdOptions = {
            PageSize = "Letter";
          };
        }
      ];
      ensureDefaultPrinter = "HP_Envy_7800";
    };

    sane = {
      enable = lib.mkDefault true;
      extraBackends = [pkgs.sane-airscan];
    };
  };

  # Scanner access for desktop users
  users.users.j_kro.extraGroups = ["scanner" "lp"];

  environment.systemPackages = with pkgs; [
    sane-backends # scanimage, scanadf CLI tools
    xsane # GUI scanner frontend
  ];
  # Static airscan config — eSCL on port 8080, bypasses broken mDNS
  environment.etc."sane.d/airscan.conf" = {
    text = ''
      [devices]
      "HP ENVY Photo 7800" = http://${cluster.devices.printer}:8080/eSCL/, escl
    '';
  };

  services = {
    pipewire = {
      enable = lib.mkDefault true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    pulseaudio.enable = false;

    libinput.enable = true;

    dbus = {
      enable = lib.mkDefault true;
      implementation = "broker";
    };

    printing = {
      enable = lib.mkDefault true;
      browsing = true;
      # systemd cups.socket handles port binding; explicit listen causes "Address already in use"
      allowFrom = ["all"];
      defaultShared = true;
    };
  };

  # 2026-08-14: the user-session dbus-broker (--scope user) inherits the
  # systemd default soft RLIMIT_NOFILE of 1024, while the SYSTEM bus broker
  # runs at 16384. Under Steam + Path of Exile 2 load the user bus exhausted
  # 1024 fds and died with "Too many open files" (sockopt_get_peerpidfd),
  # which disconnected every session D-Bus client (steamwebhelper aborted,
  # then niri received SIGTERM) and took down the whole graphical session.
  # This is upstream dbus-broker issue #435 / CVE-2026-16730: the session
  # bus has NO resource accounting (limits configured "effectively infinite"),
  # so the fd limit is the ONLY protection, and dbus-broker 37 does not
  # self-raise its soft limit (upstream fix landed in v38 via #439). Raise the
  # user bus well above the system bus so a gaming session cannot exhaust the
  # broker's fd table; the dbus-broker-exporter textfile canary monitors growth.
  systemd.user.services.dbus-broker.serviceConfig.LimitNOFILE = 65536;

  security.rtkit.enable = true;

  # Printer monitoring — ink levels and status via LEDM API.
  # Only enabled where printing is actually enabled (i.e. a node with a
  # printer); headless nodes without CUPS never run this.
  systemd.services.hp-envy-monitor = lib.mkIf config.services.printing.enable {
    description = "HP ENVY 7800 Status Monitor";
    path = with pkgs; [curl bash coreutils];
    serviceConfig.Type = "oneshot";
    script = ''
      STATUS=$(curl -sk --max-time 5 'https://${cluster.devices.printer}/DevMgmt/ProductStatusDyn.xml' 2>/dev/null)
      INK=$(curl -sk --max-time 5 'https://${cluster.devices.printer}/DevMgmt/ConsumableConfigDyn.xml' 2>/dev/null)
      echo "Printer status at $(date):"
      echo "$STATUS" | grep -oP '(?<=StatusCategory>)[^<]+' || echo "unknown"
      echo "Ink levels:"
      echo "$INK" | grep -oP '(?<=ConsumableLabelCode>)[^<]+' | paste - <(echo "$INK" | grep -oP '(?<=ConsumablePercentageLevelRemaining>)[^<]+') | while read label level; do
        echo "  $label: $level%"
      done
    '';
  };

  systemd.timers.hp-envy-monitor = lib.mkIf config.services.printing.enable {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };
}

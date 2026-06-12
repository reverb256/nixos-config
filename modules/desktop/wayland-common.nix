{
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

  security.rtkit.enable = true;

  # Printer monitoring — ink levels and status via LEDM API
  systemd.services.hp-envy-monitor = {
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

  systemd.timers.hp-envy-monitor = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };
}
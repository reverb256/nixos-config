{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  imports = [

    ./monitoring.nix
    ./firewall.nix
    ./hardware.nix
    ./desktop.nix
    ./services.nix
    ./hardware-configuration.nix
    ../../modules/services/k3s-cluster.nix
    ../../modules/services/keepalived-vip.nix
    ../../modules/system/systemd-user-timeout.nix

    ../../modules/default.nix

    ../../modules/hardware/nvidia-common.nix
    ../../modules/hardware/nvidia-wayland.nix

    ../../modules/hardware/rgb-control.nix
  ];

  clusterNetworking = {
    enable = true;
    hostName = "zephyr";
    ipAddress = "10.1.1.110";
    wireless = {
      enable = true;
      ipAddress = "10.1.1.115";
    };
    usbEthernet.enable = true;
    unbound.listenAddress = "10.1.1.110";
  };

  systemd.network.links = lib.mkForce { };


  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;
    priority = 999;
  };

  boot.kernel.sysctl = {
    "net.core.rmem_default" = 262144;
    "net.core.wmem_default" = 262144;
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;

  };

  stylix = {
    base16Scheme = "${pkgs.base16-schemes}/share/themes/nord.yaml";
    image = ../../modules/desktop/wallpapers/nord-bg.png;
  };

  networking = {
    cluster-hosts = {
      enable = true;
      populateLocal = true;
    };
  };

  profiles.node.zephyr-workstation.enable = true;

  profiles.monitoring.enable = lib.mkForce false;

  security.clusterAudit = {
    enable = true;
    enableFirewall = true;
    enableTailscaleSSH = true;
    bindServicesToLocalhost = true;
  };

  security.kubernetes.enable = true;

  security.caddyCa.enable = true;

  systemd.user.services.gamemoded = {
    wantedBy = [ "default.target" ];
  };

  fileSystems = {
    "/".options = lib.mkOptionDefault [
      "compress=zstd:3"
      "ssd"
      "discard=async"
    ];
    "/home".options = lib.mkOptionDefault [
      "compress=zstd:3"
      "ssd"
      "discard=async"
    ];
  };

  i18n.defaultLocale = "en_CA.UTF-8";

  boot.kernelPackages =
    inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-x86_64-v3;

  programs = {
    scopebuddy = {
      enable = true;
      autoDetect = {
        resolution = true;
        hdr = true;
        vrr = true;
      };
    };

    anime-game-launcher.enable = true;
    sleepy-launcher.enable = true;
    honkers-railway-launcher.enable = true;
    wavey-launcher.enable = true;

    stability-matrix.enable = true;
  };

  environment.systemPackages = with pkgs; [
    fish
    zoxide
    fzf
    eza
    btop

    tmux
    mosh
    git

    tailscale
    networkmanager
    dbus-broker
    slirp4netns
    podman-compose

    inputs.colmena.packages.${pkgs.stdenv.hostPlatform.system}.colmena
    ddcutil
    (pkgs.writeShellScriptBin "fan-set" ''
      #!${pkgs.bash}/bin/bash
      if [ "$#" -ne 2 ]; then
        echo "Usage: fan-set <fan_number> <pwm_value (0-255)>"
        echo "Example: fan-set 1 128  # Set fan 1 to 50%"
        exit 1
      fi
      fan=$1
      pwm=$2
      pwm_file="/sys/class/hwmon/hwmon6/pwm$fan"
      if [ ! -w "$pwm_file" ]; then
        echo "Error: Cannot write to $pwm_file"
        echo "You may need to disable BIOS fan control first"
        exit 1
      fi
      echo "$pwm" > "$pwm_file"
      echo "Set fan $fan to PWM $pwm ($(awk "BEGIN {printf \"%.0f\", $pwm/255*100}")%)"
    '')

    (pkgs.writeShellScriptBin "fan-get" ''
      #!${pkgs.bash}/bin/bash
      echo "Fan Status for MSI X570 TOMAHAWK:"
      echo "────────────────────────────────────────"
      for i in 1 2 3 4 5 6 7; do
        pwm_file="/sys/class/hwmon/hwmon6/pwm''$i"
        rpm_file="/sys/class/hwmon/hwmon6/fan''${i}_input"
        label_file="/sys/class/hwmon/hwmon6/fan''${i}_label"
        if [ -f "$pwm_file" ]; then
          pwm=$(cat "$pwm_file" 2>/dev/null || echo "N/A")
          rpm=$(cat "$rpm_file" 2>/dev/null || echo "0")
          label="Fan ''$i"
          [ -f "$label_file" ] && label=$(cat "$label_file")
          percent=$(awk "BEGIN {printf \"%.0f\", $pwm/255*100}")
          printf "%-12s: %4d RPM  PWM: %3d (%3s%%)\n" "$label" "$rpm" "$pwm" "$percent"
        fi
      done
    '')

    (pkgs.writeShellScriptBin "temp-get" ''
      #!${pkgs.bash}/bin/bash
      echo "Temperature Readings:"
      echo "────────────────────"
      echo "AMD CPU (k10temp):"
      ${pkgs.lm_sensors}/bin/sensors -j k10temp-pci-00c3 2>/dev/null | ${pkgs.jq}/bin/jq -r 'to_entries[] | "  \(.key): \(.value.value // .value | tonumber | floor)°C"' 2>/dev/null || ${pkgs.lm_sensors}/bin/sensors k10temp-pci-00c3
      echo ""
      echo "Motherboard (NCT6775):"
      ${pkgs.lm_sensors}/bin/sensors -j nct6797-isa-0a20 2>/dev/null | ${pkgs.jq}/bin/jq -r 'to_entries[] | select(.key | contains("temp")) | "  \(.key): \(.value.value // .value | tonumber | floor)°C"' 2>/dev/null || ${pkgs.lm_sensors}/bin/sensors nct6797-isa-0a20 | grep -E "SYSTIN|CPUTIN|TSI"
      echo ""
      echo "NVMe Drives:"
      ${pkgs.lm_sensors}/bin/sensors -j 2>/dev/null | ${pkgs.jq}/bin/jq -r 'to_entries[] | select(.key | contains("nvme")) | "  \(.key): \(.value[\"Composite\"].value | tonumber | floor)°C"' 2>/dev/null || ${pkgs.lm_sensors}/bin/sensors | grep -A2 nvme
    '')

    (pkgs.writeShellScriptBin "sys-mon" ''
      #!${pkgs.bash}/bin/bash
      exec /etc/nixos/scripts/monitor-sensors.sh
    '')

    (pkgs.writeShellScriptBin "aio-status" ''
      #!${pkgs.bash}/bin/bash
      exec /etc/nixos/scripts/corsair-status.sh
    '')

    (pkgs.writeShellScriptBin "corsair-rgb" ''
      #!${pkgs.bash}/bin/bash
      exec /etc/nixos/scripts/corsair-rgb
    '')

    (pkgs.writeShellScriptBin "corsair-rgb-server" ''
      #!${pkgs.bash}/bin/bash
      exec /etc/nixos/scripts/corsair-rgb-server
    '')

    nmap
    netdiscover
    arp-scan
    iproute2
    iputils
    dnsutils
    whois
    net-tools

    nodejs
    gh
    jq
    inputs.claude-native.packages.x86_64-linux.claude

    llama-cpp
    whisper-cpp
    pipx
    pkgs.python312Packages.huggingface-hub

    xmrig
    lolminer

    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.twilight

    python3Packages.playwright

    python312Packages.openpyxl
  ];

  networking.extraHosts = lib.mkOptionDefault ''
    127.0.0.1 search.lan search.cluster.local
    127.0.0.1 ai.lan ai.cluster.local
    127.0.0.1 openwebui.lan openwebui.cluster.local
    127.0.0.1 haven.lan haven.cluster.local
    10.1.1.100 civicintel.lan civicintel.cluster.local
  '';

  boot.postBootCommands = ''
    ${pkgs.nftables}/bin/nft add rule ip nat PREROUTING ip daddr 10.1.1.100 tcp dport 80 dnat to 10.1.1.120:30888
  '';

  system.stateVersion = "26.05";
}

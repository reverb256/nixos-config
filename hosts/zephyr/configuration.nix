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

    ../../modules/hardware/rgb-control.nix
    # inputs.nix-mineral.nixosModules.nix-mineral  # DISABLED: security-misc broke niri on NVIDIA Wayland (gen 1658+ crash)
    # ../../modules/virtualization/microvm-host.nix  # DISABLED: not yet needed, adds 1.7GB closure bloat
  ];

  # Host-specific CPU/GPU optimization for llama.cpp (Zen3: 5950X + Ampere: RTX 3090/3060 Ti)
  nixpkgs.config.packageOverrides = pkgs: {
    llama-cpp-turboquant = pkgs.llama-cpp-turboquant.overrideAttrs (old: {
      CXXFLAGS = (old.CXXFLAGS or "") + " -march=x86-64-v3 -mtune=zen3";
      cmakeFlags = (old.cmakeFlags or []) ++ [ "-DLLAMA_CUDA_ARCHITECTURES=86" ];
    });
    llama-cpp = pkgs.llama-cpp.overrideAttrs (old: {
      CXXFLAGS = (old.CXXFLAGS or "") + " -march=x86-64-v3 -mtune=zen3";
      cmakeFlags = (old.cmakeFlags or []) ++ [ "-DLLAMA_CUDA_ARCHITECTURES=86" ];
    });
  };

  # nix-mineral disabled -- security-misc hardening broke niri on NVIDIA Wayland.
  # See gen 1658+ crash investigation. Re-enable only after testing compositor startup.
  # nix-mineral = {
  #   enable = true;
  #   preset = [ "performance" "compatibility" ];
  # };

  clusterNetworking = {
    enable = true;
    hostName = "zephyr";
    ipAddress = "10.1.1.110";
    wireless = {
      enable = true;
      ipAddress = "10.1.1.115";
    };
    usbEthernet.enable = true;
    interfaceName = "eth0";
    unbound.enable = true;
    unbound.listenAddress = "10.1.1.110";
  };

  # Prevent hardware-configuration from overriding interface naming
  # while preserving the cluster-networking keep-names policy
  systemd.network.links = lib.mkForce {
    "10-keep-names" = {
      matchConfig = {
        OriginalName = "*";
      };
      linkConfig = {
        NamePolicy = "keep";
      };
    };
  };


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

  # Proton VR games require 32-bit NVIDIA driver ICD
  hardware.graphics.enable32Bit = lib.mkForce true;

  profiles.monitoring.enable = lib.mkForce false;

  security.clusterAudit = {
    enable = true;
    enableFirewall = true;
    enableTailscaleSSH = true;
    bindServicesToLocalhost = true;
  };

  security.kubernetes.enable = true;


  security.gpg.enable = true;

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

  # Shared hermes state via NFS (nexus is canonical)
  fileSystems."/home/j_kro/.hermes" = {
    device = "nexus:/data/hermes";
    fsType = "nfs4";
    options = [ "noatime" "nodiratime" "_netdev" ];
  };

  # Shared pi agent config via NFS
  fileSystems."/home/j_kro/.pi/agent" = {
    device = "nexus:/data/pi";
    fsType = "nfs4";
    options = [ "noatime" "nodiratime" "_netdev" ];
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

    lm-studio.enable = true;
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

  # Service .lan domains resolved by unbound → nexus (10.1.1.120).
  # Do NOT override to 127.0.0.1 — zephyr has no local Caddy proxy for these.

  systemd.services.dnat-nfs = {
    description = "DNAT rule for NFS redirect (10.1.1.100:80 -> 10.1.1.120:30888)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "dnat-nfs" ''
        if ! ${pkgs.nftables}/bin/nft list ruleset 2>/dev/null \
          | grep -q 'dnat to 10.1.1.120:30888'; then
          ${pkgs.nftables}/bin/nft add rule ip nat PREROUTING \
            ip daddr 10.1.1.100 tcp dport 80 \
            dnat to 10.1.1.120:30888
        fi
      '';
    };
  };

  system.stateVersion = "26.05";
}

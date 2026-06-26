{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  cluster = config.networking.cluster;
in {
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
    ../../modules/services/chatterbox-tts.nix
  ];

  # Enable Hermes RAM protection

  # Host-specific CPU/GPU optimization for llama.cpp (Zen3: 5950X + Ampere: RTX 3090/3060 Ti)
  # Note: CUDA arch already set in package via CMAKE_CUDA_ARCHITECTURES.
  # Only CPU tuning needed at host level.


  environment.sessionVariables.TZ = "America/Winnipeg";

  clusterNetworking = {
    enable = true;
    hostName = "zephyr";
    ipAddress = cluster.hosts.zephyr.ip;
    wireless = {
      enable = true;
      ipAddress = "10.1.1.115";
    };
    usbEthernet.enable = false;
    interfaceName = "eth0";
    unbound.enable = true;
    unbound.listenAddress = cluster.hosts.zephyr.ip;
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
    memoryPercent = 35;
    priority = 999;
  };

  # Boot optimization: blacklist unused kernel modules that add ~10s device timeout
  boot.blacklistedKernelModules = [
    "serial8250"     # No physical serial ports — saves ~10s timeout
    "tpm_crb"        # TPM 2.0 not used — saves ~10s timeout
    "tpm_tis"
    "tpm_tis_core"
  ];

  # Compress initrd with zstd (smaller → faster loader reads)
  boot.initrd.compressor = "zstd";

  # Limit boot entries on the 1GB ESP to prevent "No space left on device" during deploy
  boot.loader.systemd-boot.configurationLimit = 3;


  # Zram-only swap — drop disk swap on nvme1n1p1 (adds ~10s device wait)
  swapDevices = lib.mkForce [{ device = "/dev/zram0"; }];

  # Boot partition already hardened via mountOptions in disko.nix (fmask=0077)
  # systemd-cryptsetup opens with random key from /dev/urandom (no persistence needed)

  boot.kernel.sysctl = {
    "net.core.rmem_default" = 262144;
    "net.core.wmem_default" = 262144;
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;

    # Suppress martian source warnings from wlan0 (same subnet as eth0)
    "net.ipv4.conf.wlan0.rp_filter" = 2;
    "net.ipv4.conf.all.log_martians" = lib.mkForce false;
  };

  # Enable i686 emulation so local builds can compile 32-bit packages (Steam, Wine)
  boot.binfmt.emulatedSystems = ["i686-linux"];

  stylix = {
    base16Scheme = {
      base00 = "111c18";
      base01 = "23372B";
      base02 = "53685B";
      base03 = "53685B";
      base04 = "ACD4CF";
      base05 = "C1C497";
      base06 = "D7C995";
      base07 = "F6F5DD";
      base08 = "FF5345";
      base09 = "db9f9c";
      base0A = "E5C736";
      base0B = "549e6a";
      base0C = "2DD5B7";
      base0D = "509475";
      base0E = "D2689C";
      base0F = "9eebb3";
    };
    image = ../../modules/desktop/wallpapers/osaka-jade-bg.jpg;
    enableReleaseChecks = false;
  };

  networking = {
    cluster-hosts = {
      enable = true;
      populateLocal = true;
    };
    # Block Hoyoverse telemetry domains (Genshin Impact, Honkai Star Rail, Zenless Zone Zero)
    # Disabled for zephyr (workstation) to allow anime game launchers with telemetry
    # hoyoverse-telemetry-block.enable = true;
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

  security.gpg.enable = true;

  systemd.user.services.gamemoded = {
    wantedBy = ["default.target"];
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

  # Bind mount for NFS export (hermes state lives in ~/)
  fileSystems."/data/hermes" = {
    device = "/home/j_kro/.hermes";
    fsType = "none";
    options = ["bind" "rw"];
  };

  # Gammix subvolume mounts for games + projects
  # XPG GAMMIX S11 Pro — secondary drive for games + projects
  fileSystems."/data/games" = {
    device = "/dev/disk/by-label/nix";
    fsType = "btrfs";
    options = ["subvol=@games" "compress=zstd:3" "ssd" "discard=async" "noatime" "nofail"];
  };
  fileSystems."/data/projects" = {
    device = "/dev/disk/by-label/nix";
    fsType = "btrfs";
    options = ["subvol=@projects" "compress=zstd:3" "ssd" "discard=async" "noatime" "nofail"];
  };

  services.nixos-share = {
    enable = lib.mkForce false;
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
        vrr = false;
      };
    };

    anime-game-launcher.enable = true;
    honkers-railway-launcher.enable = true;
    wavey-launcher.enable = true;
    sleepy-launcher.enable = true;

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

    imv
    mpv

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

    pkgs.zen-twilight

    python3Packages.playwright

    python312Packages.openpyxl

    nvtopPackages.full
  ];

  # Service .lan domains resolved by unbound → nexus (${cluster.hosts.nexus.ip}).
  # Do NOT override to 127.0.0.1 — zephyr has no local Caddy proxy for these.

  # dnat-nfs and dnat-caddy-ingress DISABLED — host Caddy proxies .lan domains
  # via NodePort (30080). Old DNAT rules pointed to stale pod IPs and conflicted
  # with the host-level Caddy reverse proxy.

  system.stateVersion = "26.05";
  # unbound-common disabled for zephyr — cluster-dns.nix (via clusterNetworking.unbound.enable)
  # provides identical upstream forwarding PLUS cluster.local K8s DNS forwarding.
  # Both active = duplicate forward zone errors on every boot.
  # Other hosts (nexus, forge, sentry) still use unbound-common.
  services.unbound-common.enable = lib.mkForce false;
  # Enable Hermes RAM protection (mandatory pre-flight checks)
  # CNS: Zero-knowledge automatic secret distribution
  services.ai-inference.enable = lib.mkForce false;
  services.cluster-mesh.enable = true;
  services.cluster-ca.enable = true;

  # ═══════════════════════════════════════════════════════════════════
  # STORAGE REDIRECT — Secondary NVMe for heavy data
  # System: Samsung SSD 980 1TB (nvme1n1, label "root") — 70%, 280G free
  # Secondary: XPG GAMMIX S11 Pro 1TB (nvme0n1, label "nix") — 44%, 511G free
  #   /nix (85G store), /var, /data/games, /data/projects on XPG
  #   /, /home on Samsung
  # ═══════════════════════════════════════════════════════════════════
  fileSystems."/nix" = lib.mkForce {
    device = "/dev/disk/by-label/nix";
    fsType = "btrfs";
    options = ["subvol=@nix" "compress=zstd" "noatime" "x-initrd.mount" "nofail"];
  };

  # Mount /var on the secondary NVMe — frees ~22G on the system drive
  # Covers: /var/lib/rancher (k3s), /var/lib/flatpak, /var/lib/nix-csi
  fileSystems."/var" = lib.mkForce {
    device = "/dev/disk/by-label/nix";
    fsType = "btrfs";
    options = ["subvol=@var" "compress=zstd" "noatime" "x-initrd.mount" "nofail"];
  };

  # System fonts - enable fontconfig and install packages
  fonts = {
    fontconfig.enable = true;
    packages = [
      pkgs.inter
      pkgs.nerd-fonts.jetbrains-mono
      pkgs.dejavu_fonts
      pkgs.noto-fonts-color-emoji
      pkgs.source-sans
      pkgs.source-serif
      pkgs.source-han-sans
      pkgs.source-han-serif
    ];
  };}


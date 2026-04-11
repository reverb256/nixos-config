# Zephyr Host Configuration
# RTX 3090, Quest Pro, 4K HDR TV
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  imports = [
    # ========================================================================
    # BASE MODULES
    # ========================================================================

    # Monitoring configuration
    ./monitoring.nix
    # Firewall rules
    ./firewall.nix
    # Hardware configuration (GPU, RGB, AIO, Bluetooth, kernel modules)
    ./hardware.nix
    # Desktop and display (Wayland compositors, HDR, flatpak)
    ./desktop.nix
    # Services (Kubernetes, AI inference, mining, backup, apps)
    ./services.nix
    # Hardware configuration (generated)
    ./hardware-configuration.nix
    # Kubernetes control plane
    ../../modules/services/k3s-cluster.nix
    # Keepalived VIP for Kubernetes HA
    ../../modules/services/keepalived-vip.nix
    # FIX: Systemd user unit reload timeout (nixos-rebuild switch hang)
    ../../modules/system/systemd-user-timeout.nix

    # All other modules auto-imported via ../../modules/default.nix
    # This includes: system, desktop, shell, gaming, development, services,
    # plus zephyr-specific modules (nvidia-common, gstreamer, spotify, cluster networking)
    ../../modules/default.nix

    # NVIDIA GPU Wayland support (host-dependent)
    ../../modules/hardware/nvidia-common.nix
    ../../modules/hardware/nvidia-wayland.nix

    # RGB control for peripherals and components
    ../../modules/hardware/rgb-control.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  # Centralized cluster networking (search domains, DNS, firewall basics)
  # Note: interfaceName provided by node-profiles.zephyr-workstation
  clusterNetworking = {
    enable = true;
    hostName = "zephyr";
    ipAddress = "10.1.1.110";
    wireless = {
      enable = true;
      ipAddress = "10.1.1.115"; # Static IP for WiFi backup
    };
    usbEthernet.enable = true; # Support USB ethernet adapters
    unbound.listenAddress = "10.1.1.110";
  };

  # FIX: Disable interface renaming - use actual interface names
  systemd.network.links = lib.mkForce { };

  # ============================================================================
  # MEMORY OPTIMIZATION - zram compressed swap + kernel tuning
  # ============================================================================
  # VM sysctls (vfs_cache_pressure, swappiness, overcommit) handled by
  # vm-tuning.nix with mkForce — only host-specific overrides here.
  # Previous vfs_cache_pressure=1000 caused excessive page cache eviction,
  # forcing more SSD swap. vm-tuning.nix sets 150 (mkForce).

  # ZRAM compressed swap — reduces SSD wear, faster than disk swap
  # 25% of 31GB ≈ 8GB compressed swap (zstd compression ~2-3x ratio)
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;
    priority = 999; # Prefer zram over disk swap
  };

  boot.kernel.sysctl = {
    # Network buffer tuning (frees unused socket buffers)
    "net.core.rmem_default" = 262144; # 256KB (default: 212992)
    "net.core.wmem_default" = 262144; # 256KB
    "net.core.rmem_max" = 16777216; # 16MB max
    "net.core.wmem_max" = 16777216;

    # CALICO CNI REQUIREMENTS
    "net.ipv4.conf.all.rp_filter" = 1; # Reverse path filtering for BGP
  };

  networking = {
    cluster-hosts = {
      enable = true;
      populateLocal = true;
    };
  };

  # ============================================================================
  # NODE PROFILE - Platform-level defaults
  # ============================================================================
  # This profile bundles role profiles, Kubernetes config, hardware profiles,
  # and networking configuration. Eliminates ~100 lines of duplication.
  profiles.node.zephyr-workstation.enable = true;

  # MONITORING DISABLED - Protect 31GB RAM for gaming/VR/AI workloads
  # Monitoring stack moved to Nexus (46GB RAM) to prevent OOM on Zephyr
  # Prometheus/Grafana running on Kubernetes (ai-inference namespace)
  # AlertManager running on Nexus via monitoring profile
  profiles.monitoring.enable = lib.mkForce false;

  # ============================================================================
  # SECURITY AUDIT REMEDIATION
  # ============================================================================
  # Enables firewall, Tailscale SSH, and service hardening
  security.clusterAudit = {
    enable = true;
    enableFirewall = true;
    enableTailscaleSSH = true;
    bindServicesToLocalhost = true;
  };

  # Kubernetes security tools for runtime monitoring
  security.kubernetes.enable = true;

  # Trust Caddy Ingress local CA certificate
  security.caddyCa.enable = true;

  # ============================================================================
  # SYSTEMD - Service overrides
  # ============================================================================
  # GameMode daemon - Start at boot for gaming-detection service
  systemd.user.services.gamemoded = {
    wantedBy = [ "default.target" ];
  };

  # ============================================================================
  # FILESYSTEM COMPRESSION - Enable zstd on all BTRFS filesystems
  # ============================================================================
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

  # ============================================================================
  # LOCALE
  # ============================================================================
  i18n.defaultLocale = "en_CA.UTF-8";

  # ============================================================================
  # BOOT CONFIGURATION
  # ============================================================================
  # NOTE: Using CachyOS kernel for better sched_ext/scx_lavd support.
  # Uses the flake input's linuxPackages directly to hit the binary cache.
  boot.kernelPackages =
    inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-x86_64-v3;

  # ============================================================================
  # PROGRAMS - SCOPEBUDDY, ANIME GAME LAUNCHERS, AI SERVICES
  # ============================================================================
  programs = {
    scopebuddy = {
      enable = true;
      autoDetect = {
        resolution = true;
        hdr = true;
        vrr = true;
      };
    };

    # Anime game launchers
    anime-game-launcher.enable = true;
    sleepy-launcher.enable = true;
    honkers-railway-launcher.enable = true;
    wavey-launcher.enable = true;

    # AI services
    stability-matrix.enable = true;
  };

  # ============================================================================
  # ADDITIONAL PACKAGES
  # ============================================================================
  environment.systemPackages = with pkgs; [
    # Shell & CLI
    fish
    zoxide
    fzf
    eza
    btop

    # Version control
    tmux
    mosh
    git

    # Networking
    tailscale
    networkmanager
    dbus-broker
    slirp4netns # Required for Spacebot/Podman networking
    podman-compose # Docker Compose compatibility for Podman
    localsend # Local network file sharing (AirDrop alternative)

    # Deployment
    inputs.colmena.packages.${pkgs.stdenv.hostPlatform.system}.colmena
    (pkgs.writeShellScriptBin "spacebot" ''
      #!${pkgs.bash}/bin/bash
      # Spacebot CLI wrapper - connects to local Spacebot service
      exec ${pkgs.curl}/bin/curl --data-binary @- http://127.0.0.1:19898/api/run "$@"
    '')

    # Hardware monitoring & fan control helpers
    ddcutil # DDC/CI monitor brightness control
    (pkgs.writeShellScriptBin "fan-set" ''
      #!${pkgs.bash}/bin/bash
      # Set fan speed (0-255) for a specific fan
      # Usage: fan-set <fan_number> <pwm_value>
      # Example: fan-set 1 128 (sets fan 1 to 50%)
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
      # Get current fan speed and PWM for all fans
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
      # Get all temperature readings
      echo "Temperature Readings:"
      echo "────────────────────"
      # AMD CPU temps
      echo "AMD CPU (k10temp):"
      ${pkgs.lm_sensors}/bin/sensors -j k10temp-pci-00c3 2>/dev/null | ${pkgs.jq}/bin/jq -r 'to_entries[] | "  \(.key): \(.value.value // .value | tonumber | floor)°C"' 2>/dev/null || ${pkgs.lm_sensors}/bin/sensors k10temp-pci-00c3
      echo ""
      # Motherboard temps
      echo "Motherboard (NCT6775):"
      ${pkgs.lm_sensors}/bin/sensors -j nct6797-isa-0a20 2>/dev/null | ${pkgs.jq}/bin/jq -r 'to_entries[] | select(.key | contains("temp")) | "  \(.key): \(.value.value // .value | tonumber | floor)°C"' 2>/dev/null || ${pkgs.lm_sensors}/bin/sensors nct6797-isa-0a20 | grep -E "SYSTIN|CPUTIN|TSI"
      echo ""
      # NVMe temps
      echo "NVMe Drives:"
      ${pkgs.lm_sensors}/bin/sensors -j 2>/dev/null | ${pkgs.jq}/bin/jq -r 'to_entries[] | select(.key | contains("nvme")) | "  \(.key): \(.value[\"Composite\"].value | tonumber | floor)°C"' 2>/dev/null || ${pkgs.lm_sensors}/bin/sensors | grep -A2 nvme
    '')

    (pkgs.writeShellScriptBin "sys-mon" ''
      #!${pkgs.bash}/bin/bash
      # Comprehensive system monitoring dashboard
      exec /etc/nixos/scripts/monitor-sensors.sh
    '')

    (pkgs.writeShellScriptBin "aio-status" ''
      #!${pkgs.bash}/bin/bash
      # Corsair AIO cooler status
      exec /etc/nixos/scripts/corsair-status.sh
    '')

    (pkgs.writeShellScriptBin "corsair-rgb" ''
      #!${pkgs.bash}/bin/bash
      # Start OpenRGB GUI for Corsair RGB control
      exec /etc/nixos/scripts/corsair-rgb
    '')

    (pkgs.writeShellScriptBin "corsair-rgb-server" ''
      #!${pkgs.bash}/bin/bash
      # Start OpenRGB server for programmatic RGB control
      exec /etc/nixos/scripts/corsair-rgb-server
    '')

    # Network discovery & mapping
    nmap
    netdiscover
    arp-scan
    iproute2 # ip, ss, route commands
    iputils # ping, traceroute
    dnsutils # dig, nslookup
    whois
    net-tools # arp, ifconfig, route

    # Development
    nodejs
    gh
    jq
    inputs.claude-native.packages.x86_64-linux.claude

    # AI & ML
    llama-cpp
    whisper-cpp
    pipx
    pkgs.python312Packages.huggingface-hub # HF CLI: hf download/upload/login
    opencode # AI coding agent (terminal-based)

    # Mining (manual only, no auto-start)
    xmrig
    lolminer

    # Desktop
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.twilight
    telegram-desktop

    # Network automation - for switch/modem configuration scripts
    python3Packages.playwright

    # Diagrams & data
    mermaid-cli # Mermaid → SVG/PNG
    graphviz # Graphviz (dot) diagrams
    python312Packages.openpyxl # Excel read/write
  ];

  # ============================================================================
  # DNS - Local records for K8s ingress hostnames
  # ============================================================================
  networking.extraHosts = lib.mkOptionDefault ''
    10.1.1.100 search.lan search.cluster.local
    10.1.1.100 ai.lan ai.cluster.local
    10.1.1.100 openwebui.lan openwebui.cluster.local
    10.1.1.100 civicintel.lan civicintel.cluster.local
  '';

  # ============================================================================
  # SYSTEM STATE
  # ============================================================================
  system.stateVersion = "26.05";
}
# Force rebuild - Thu 12 Mar 2026 09:59:02 PM UTC

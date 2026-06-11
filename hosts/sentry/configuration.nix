{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.disko.nixosModules.disko
    ./monitoring.nix
    ./firewall.nix
    ./hardware.nix
    ./desktop.nix
    ./services.nix
    ./hardware-configuration.nix
    ./disko.nix
    ./preservation.nix

    ../../modules/default.nix

    ../../modules/hardware/rgb-control.nix

    ../../modules/services/podman-support.nix

    ../../modules/services/k3s-cluster.nix
    ../../modules/services/keepalived-vip.nix
    ../../modules/services/sshfs-projects-mount.nix
    inputs.nix-mineral.nixosModules.nix-mineral
  ];

  stylix = {
    base16Scheme = "${pkgs.base16-schemes}/share/themes/dracula.yaml";
    image = ../../modules/desktop/wallpapers/dracula-bg.png;
  };

  clusterNetworking = {
    enable = true;
    hostName = "sentry";
    ipAddress = config.networking.cluster.hosts.sentry.ip;
    interfaceName = "eth0";
    wireless.enable = false;
    unbound.enable = true;
    unbound.listenAddress = config.networking.cluster.hosts.sentry.ip;
  };

  # Block Hoyoverse telemetry domains (Genshin Impact, Honkai Star Rail, Zenless Zone Zero)
  networking.hoyoverse-telemetry-block.enable = true;

  # Declarative static IP for eth0 — NM connection persisted across rebuilds
  environment.etc."NetworkManager/system-connections/static-eth0.nmconnection" = {
    mode = "0600";
    text = ''
      [connection]
      id=static-eth0
      type=ethernet
      interface-name=eth0

      [ethernet]

      [ipv4]
      method=manual
      addresses=${config.networking.cluster.hosts.sentry.ip}/24
      gateway=10.1.1.1
      dns=127.0.0.1

      [ipv6]
      method=auto
    '';
  };

  services.flake-lock-sync.enable = true;
  systemd.timers.flake-lock-sync.enable = true;

  # Kanban automation — execute ready tasks every 15 minutes
  systemd.services.kanban-execute = {
    description = "MapleSpike Kanban Task Executor";
    path = [ pkgs.bash pkgs.jq ];
    script = ''
      exec /home/j_kro/projects/maplespike/scripts/kanban-execute.sh
    '';
    serviceConfig = {
      User = "j_kro";
      Group = "users";
      Type = "oneshot";
      WorkingDirectory = "/home/j_kro/projects/maplespike";
    };
  };
  systemd.timers.kanban-execute = {
    description = "Run kanban executor every 15 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "minute:0/15";
      Persistent = true;
    };
  };


  # Fix system clock on boot if RTC is not battery-backed and time is wildly wrong.
  # NTP cannot correct a 9-year skew, so we pre-set to the build time of the current
  # NixOS generation first, then let timesyncd fine-tune from there.
  systemd.services.fix-system-clock = {
    description = "Fix system clock if wildly inaccurate (no battery-backed RTC)";
    after = [ "systemd-timesyncd.service" ];
    wants = [ "systemd-timesyncd.service" ];
    before = [ "unbound.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if [ "$(date +%Y)" -lt 2026 ]; then
        BUILD_TIME="$(stat -c %Y /run/current-system 2>/dev/null || echo 0)"
        if [ "$BUILD_TIME" -gt 0 ]; then
          date -s "@$BUILD_TIME"
        fi
      fi
    '';
  };

  profiles.node.sentry-monitoring.enable = true;

  services.ai-inference.enable = lib.mkForce false;

  # ═══════════════════════════════════════════════════════════════════
  # STORAGE — Managed by disko.nix
  # System SSD: Micron 1100 SATA 256GB (sdb, /dev/disk/by-id/ata-Micron_1100_SATA_256GB_18361E518AB4)
  # Storage HDD: ST1000DM010 1TB (sda, /dev/disk/by-id/ata-ST1000DM010-2EP102_ZN1AMQLC)
  # ═══════════════════════════════════════════════════════════════════
  # Subvolumes on SSD: @root (/), @persistent (/persistent), @nix (/nix)
  # Subvolumes on HDD: @home (/home)
  # /storage is manually mounted in hardware-configuration.nix
  # /var is on SSD (default)

  boot.kernelPackages =
    inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-x86_64-v3;
  boot.loader.timeout = lib.mkDefault 5;

  services.sshfs-projects-mount.enable = true;

  services.nfs-cluster-mounts = {
    enable = true;
    mountHermes = false;
    mountPi = false;
  };

  # Hardware watchdog — auto-reboot after 60s of system hang
  # SP5100 TCO timer feeds via systemd, recovers from GPU/PCIe lockups
  systemd.settings.Manager.RuntimeWatchdogSec = 60;

  # System hardening
  nix-mineral = {
    enable = true;
    preset = ["compatibility"];
    settings.etc.kicksecure-module-blacklist = false;
    filesystems.normal = {
      "/etc".enable = lib.mkForce false;
      "/home".enable = lib.mkForce false;
      "/root".enable = lib.mkForce false;
      "/srv".enable = lib.mkForce false;
      "/tmp".enable = lib.mkForce false;
      "/var".enable = lib.mkForce false;
      "/var/lib".enable = lib.mkForce false;
      "/var/log".enable = lib.mkForce false;
      "/var/tmp".enable = lib.mkForce false;
    };
  };

  systemd.services.nfs-idmapd.serviceConfig.SupplementaryGroups = ["proc"];
  systemd.tmpfiles.rules = ["d /var/lib/nfs/rpc_pipefs/nfs 0755 root root -"];


  programs.git.config = {
    user = {
      name = lib.mkForce "Jeremy Kroeker";
      email = "jkroeker@proton.me";
    };
  };

  system.stateVersion = "26.05";
  services.unbound-common.enable = true;



  # Mark CDN domains with broken DNSSEC as domain-insecure so unbound
  # doesnt reject their CNAME-chained A records (e.g. cache.nixos.org -> fastly.net)
  services.unbound.settings.server.domain-insecure = [
    "fastly.net"
    "nixos.org"
  ];

  services.unbound.settings.forward-zone = lib.mkForce [
    {
      name = "ts.net.";
      forward-addr = ["100.100.100.100" "fd7a:115c:a1e0::53"];
    }
    {
      name = ".";
      forward-addr = ["1.1.1.1" "1.0.0.1" "8.8.8.8" "8.8.4.4"];
    }
  ];

  security.clusterAudit = {
    enable = true;
    enableFirewall = true;
    enableTailscaleSSH = true;
    bindServicesToLocalhost = true;
  };

  # Resolve gitconfig conflict
  environment.etc.gitconfig.source = lib.mkForce (pkgs.writeText "gitconfig" "'[safe]
  directory = /etc/nixos
'");
  environment.systemPackages = with pkgs; [
    nvtopPackages.full
  ];

  users.users.j_kro.extraGroups = [
    "hermes"
  ];

  services.hermes-agent = {
    enable = true;
    addToSystemPackages = true;
    settings = {
      model = {
        default = "nvidia/nemotron-3-super-120b-a12b";
        provider = "nvidia";
      };
      memory = {
        memory_enabled = true;
        user_profile_enabled = true;
        memory_char_limit = 2200;
        user_char_limit = 1375;
        provider = "openviking";
      };
      terminal = {
        backend = "local";
        timeout = 60;
      };
      kanban = {
        dispatch_in_gateway = true;
        dispatch_interval_seconds = 60;
        failure_limit = 2;
      };
      display = {
        compact = false;
        interface = "cli";
      };
    };
  };

  services.hermes-agent.settings = {
    providers = {
      nvidia = {
        base_url = "https://integrate.api.nvidia.com/v1";
        api_key_env = "NVIDIA_API_KEY";
        context_length = 1048576;
        discover_models = true;
      };
      zai = {
        base_url = "https://api.z.ai/api/coding/paas/v4";
        api_key_env = "ZAI_API_KEY";
        context_length = 131072;
        discover_models = true;
      };
      kilocode = {
        base_url = "https://api.kilocode.ai/v1";
      };
    };
    fallback_providers = [
      "nvidia"
      "zai"
    ];
    auxiliary = {
      vision = {
        provider = "nvidia";
        model = "meta/llama-3.2-90b-vision-instruct";
        base_url = "https://integrate.api.nvidia.com/v1";
        timeout = 120;
      };
      web_extract = {
        provider = "nvidia";
        model = "nvidia/nemotron-3-super-120b-a12b";
        base_url = "https://integrate.api.nvidia.com/v1";
        timeout = 120;
      };
      compression = {
        provider = "nvidia";
        model = "nvidia/nemotron-3-super-120b-a12b";
        base_url = "https://integrate.api.nvidia.com/v1";
        timeout = 60;
      };
      skills_hub = {
        provider = "nvidia";
        model = "nvidia/nemotron-3-super-120b-a12b";
        base_url = "https://integrate.api.nvidia.com/v1";
        timeout = 30;
      };
      approval = {
        provider = "nvidia";
        model = "nvidia/nemotron-3-super-120b-a12b";
        base_url = "https://integrate.api.nvidia.com/v1";
        timeout = 30;
      };
      mcp = {
        provider = "nvidia";
        model = "mistralai/ministral-14b-instruct-2512";
        base_url = "https://integrate.api.nvidia.com/v1";
        timeout = 30;
      };
      title_generation = {
        provider = "nvidia";
        model = "nvidia/nemotron-3-super-120b-a12b";
        base_url = "https://integrate.api.nvidia.com/v1";
        timeout = 30;
      };
      triage_specifier = {
        provider = "nvidia";
        model = "nvidia/nemotron-3-super-120b-a12b";
        base_url = "https://integrate.api.nvidia.com/v1";
        timeout = 120;
      };
      kanban_decomposer = {
        provider = "nvidia";
        model = "qwen/qwen3.5-122b-a10b";
        base_url = "https://integrate.api.nvidia.com/v1";
        timeout = 180;
      };
      profile_describer = {
        provider = "nvidia";
        model = "nvidia/nemotron-3-super-120b-a12b";
        base_url = "https://integrate.api.nvidia.com/v1";
        timeout = 30;
      };
      curator = {
        provider = "nvidia";
        model = "nvidia/nemotron-3-super-120b-a12b";
        base_url = "https://integrate.api.nvidia.com/v1";
        timeout = 300;
      };
    };
  };

  # Disable all forms of suspend
  powerManagement.enable = false;
  services.logind.settings = {
    Login = {
      HandleLidSwitch = "ignore";
      HandleLidSwitchExternalPower = "ignore";
      HandleLidSwitchDocked = "ignore";
      IdleAction = "ignore";
    };
  };
  systemd.targets.sleep.enable = false;
  systemd.targets.suspend.enable = false;
  systemd.targets.hibernate.enable = false;
  systemd.targets.hybrid-sleep.enable = false;
}

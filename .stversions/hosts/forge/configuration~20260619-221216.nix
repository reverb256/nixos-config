{
  config,
  lib,
  pkgs,
  inputs,
  ...

}: {
  environment.sessionVariables.TZ = "America/Winnipeg";

  imports = [
    inputs.disko.nixosModules.disko
    ./monitoring.nix
    ./firewall.nix
    ./hardware.nix
    ./desktop.nix
    ./services.nix
    ./disko.nix
    ./preservation.nix

    ../../modules/default.nix
    ../../modules/hardware/rgb-control.nix
    ../../modules/services/podman-support.nix
    ../../modules/services/k3s-cluster.nix
    ../../modules/services/keepalived-vip.nix
    ../../modules/services/sshfs-projects-mount.nix
  ];

  # Host-specific CPU/GPU optimization for llama.cpp (Zen1 + Ada: RTX 4060)
  nixpkgs.config.packageOverrides = pkgs: {
    llama-cpp-turboquant = pkgs.llama-cpp-turboquant.overrideAttrs (old: {
      CXXFLAGS = (old.CXXFLAGS or "") + " -march=x86-64-v3";
    });
    llama-cpp = pkgs.llama-cpp.overrideAttrs (old: {
      CXXFLAGS = (old.CXXFLAGS or "") + " -march=x86-64-v3";
    });
    llama-cpp-vulkan = pkgs.llama-cpp-vulkan.overrideAttrs (old: {
      CXXFLAGS = (old.CXXFLAGS or "") + " -march=x86-64-v3";
    });
  };

  stylix = {
    base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-medium.yaml";
    image = ../../modules/desktop/wallpapers/gruvbox-dark-bg.png;
  };

  clusterNetworking = {
    enable = true;
    hostName = "forge";
    ipAddress = config.networking.cluster.hosts.forge.ip;
    interfaceName = lib.mkForce "eno1";
    wireless.enable = false;
    unbound.enable = true;
    unbound.listenAddress = config.networking.cluster.hosts.forge.ip;
  };

  # Block Hoyoverse telemetry domains (Genshin Impact, Honkai Star Rail, Zenless Zone Zero)
  networking.hoyoverse-telemetry-block.enable = true;

  networking.interfaces.eno1.ipv6.addresses = [
    {
      address = "fd00::130";
      prefixLength = 64;
    }
  ];

  boot.kernel.sysctl."net.ipv6.conf.all.disable_ipv6" = 0;
  boot.kernel.sysctl."net.ipv6.conf.default.disable_ipv6" = 0;
  boot.kernel.sysctl."net.ipv6.conf.eno1.disable_ipv6" = 0;

  systemd.timers.flake-lock-sync.enable = true;
  services.flake-lock-sync.enable = true;

  kernel-hardening.zswap.maxPoolPercent = 20;

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;
    priority = 999;
  };

  services.earlyoom = {
    enable = true;
    freeSwapThreshold = 10;
    enableNotifications = true;
  };

  boot.kernel.sysctl."vm.min_free_kbytes" = lib.mkForce 524288;

  profiles.node.forge-mining.enable = true;
  services.ai-inference.backend.type = "llama-cpp";

  boot.kernelPackages =
    inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-x86_64-v3;

  services.sshfs-projects-mount.enable = true;

  services.nfs-cluster-mounts = {
    enable = true;
    mountHermes = false;
    mountPi = false;
  };

  # Override noexec on /var for k3s re-exec
  fileSystems."/var/lib/rancher/k3s" = {
    device = "/var/lib/rancher/k3s";
    fsType = "none";
    options = ["bind" "rw" "nosuid"];
  };

  system.stateVersion = "26.05";
  services.unbound-common.enable = true;

  # STORAGE — Managed by disko.nix
  # System SSD: TEAM T253X2256G 256GB (sdb) — @root, @persistent, @nix
  # Storage HDD: ADATA SU635 240GB (sda) — @home, @var, @games

  nix.settings.auto-optimise-store = true;
  boot.resumeDevice = "/dev/disk/by-id/ata-TEAM_T253X2256G_TM701907310240040386-part2";
  disabledModules = [ "services/kmscon" ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}

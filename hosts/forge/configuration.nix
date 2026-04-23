{
  lib,
  pkgs,
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
    ../../modules/default.nix
    ../../modules/hardware/rgb-control.nix
    ../../modules/system/security.nix
    ../../modules/services/podman-support.nix
    ../../modules/services/k3s-cluster.nix
    inputs.nix-mineral.nixosModules.nix-mineral
  ];

  stylix = {
    base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-medium.yaml";
    image = ../../modules/desktop/wallpapers/gruvbox-dark-bg.png;
  };

  clusterNetworking = {
    enable = true;
    hostName = "forge";
    ipAddress = "10.1.1.130";
    interfaceName = lib.mkForce "eno1";
    wireless.enable = false;
    unbound.listenAddress = "10.1.1.130";
  };

  networking.interfaces.eno1.ipv6.addresses = [
    {
      address = "fd00::130";
      prefixLength = 64;
    }
  ];

  boot.kernel.sysctl."net.ipv6.conf.all.disable_ipv6" = 0;
  boot.kernel.sysctl."net.ipv6.conf.default.disable_ipv6" = 0;
  boot.kernel.sysctl."net.ipv6.conf.eno1.disable_ipv6" = 0;

  systemd.timers.flake-lock-sync.enable = false;

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

  # System hardening (Phase 0: Security Baseline)
  # Preset: default + performance (base hardening, relaxed PTI/CPU mitigations for mining)
  nix-mineral = {
    enable = true;
    preset = [ "default" "performance" ];
  };

  # Resolve gitconfig conflict between NixOS default and nix-mineral
  environment.etc.gitconfig.source = lib.mkForce (pkgs.writeText "gitconfig" ''
    [user]
      name = Jeremy Kroeker
      email = jkroeker@proton.me
  '');

  system.stateVersion = "26.05";
}

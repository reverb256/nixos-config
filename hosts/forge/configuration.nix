{
  config,
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
    ../../modules/services/podman-support.nix
    ../../modules/services/k3s-cluster.nix
  ];

  # Host-specific CPU/GPU optimization for llama.cpp (Zen1 + Ada: RTX 4060)
  nixpkgs.config.packageOverrides = pkgs: {
    llama-cpp-turboquant = pkgs.llama-cpp-turboquant.overrideAttrs (old: {
      CXXFLAGS = (old.CXXFLAGS or "") + " -march=x86-64-v3";
      cmakeFlags = (old.cmakeFlags or []) ++ [ "-DLLAMA_CUDA_ARCHITECTURES=89" ];
    });
    llama-cpp = pkgs.llama-cpp.overrideAttrs (old: {
      CXXFLAGS = (old.CXXFLAGS or "") + " -march=x86-64-v3";
      cmakeFlags = (old.cmakeFlags or []) ++ [ "-DLLAMA_CUDA_ARCHITECTURES=89" ];
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
    ipAddress = "10.1.1.130";
    interfaceName = lib.mkForce "eno1";
    wireless.enable = false;
    unbound.enable = true;
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

  # nix-mineral DISABLED on forge (same as zephyr)
  # Reason: NixOS 26.05 PAM/apparmor strict checking breaks
  # nix-mineral's non-absolute modulePath 'login'
  # nix-mineral = { enable = true; preset = [ 'default' 'performance' ]; };

  # Override noexec on /var (nix-mineral remnant) for k3s re-exec
  fileSystems."/var/lib/rancher/k3s" = {
    device = "/var/lib/rancher/k3s";
    fsType = "none";
    options = [ "bind" "rw" "nosuid" ];
  };

  system.stateVersion = "26.05";
  services.unbound-common.enable = true;
}

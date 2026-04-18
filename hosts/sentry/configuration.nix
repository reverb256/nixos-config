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

    ../../modules/hardware/amdgpu-wayland.nix
    ../../modules/hardware/rgb-control.nix

    ../../modules/services/podman-support.nix

    ../../modules/services/k3s-cluster.nix
    ../../modules/services/keepalived-vip.nix
  ];

  stylix = {
    base16Scheme = "${pkgs.base16-schemes}/share/themes/dracula.yaml";
    image = ../../modules/desktop/wallpapers/dracula-bg.png;
  };


  clusterNetworking = {
    enable = true;
    hostName = "sentry";
    ipAddress = "10.1.1.140";
    interfaceName = "enp7s0";
    wireless.enable = false;
    unbound.listenAddress = "10.1.1.140";
  };

  services.flake-lock-sync.enable = lib.mkForce false;
  systemd.timers.flake-lock-sync.enable = false;

  profiles.node.sentry-monitoring.enable = true;

  services.ai-inference = {
    enable = true;
    backend = {
      type = "llama-cpp";
      url = "http://127.0.0.1:1235";
      local = {
        model = "Qwen3.5-4B.Q4_K_M.gguf";
        url = "http://127.0.0.1:1235";
      };
    };
    gateway = {
      host = "0.0.0.0";
      port = 8080;
    };
  };

  boot.kernelPackages =
    inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-x86_64-v3;
  boot.loader.timeout = lib.mkDefault 5;


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
  system.stateVersion = "26.05";
}

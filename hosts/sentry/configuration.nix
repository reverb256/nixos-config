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

    ../../modules/services/podman-support.nix

    ../../modules/services/k3s-cluster.nix
    ../../modules/services/keepalived-vip.nix
    inputs.nix-mineral.nixosModules.nix-mineral
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

  services.ai-inference.enable = lib.mkForce false;

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

  # System hardening (Phase 0: Security Baseline)
  # Preset: compatibility (desktop + monitoring)
  nix-mineral = {
    enable = true;
    preset = [ "compatibility" ];
  };

  # Resolve gitconfig conflict between NixOS default and nix-mineral
  environment.etc.gitconfig.source = lib.mkForce (pkgs.writeText "gitconfig" ''
    [user]
      name = Jeremy Kroeker
      email = jkroeker@proton.me
  '');

  system.stateVersion = "26.05";
}

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
    ../../modules/services/keepalived-vip.nix
    inputs.nix-mineral.nixosModules.nix-mineral
  ];

  # Host-specific CPU/GPU optimization for llama.cpp (Intel 9500f + AMD RX 5600 XT)
  nixpkgs.config.packageOverrides = pkgs: {
    llama-cpp-turboquant = pkgs.llama-cpp-turboquant.overrideAttrs (old: {
      CXXFLAGS = (old.CXXFLAGS or "") + " -march=x86-64-v3 -mtune=haswell";
    });
    llama-cpp = pkgs.llama-cpp.overrideAttrs (old: {
      CXXFLAGS = (old.CXXFLAGS or "") + " -march=x86-64-v3 -mtune=haswell";
    });
    llama-cpp-vulkan = pkgs.llama-cpp-vulkan.overrideAttrs (old: {
      CXXFLAGS = (old.CXXFLAGS or "") + " -march=x86-64-v3 -mtune=haswell";
    });
  };

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
    unbound.enable = true;
    unbound.listenAddress = "10.1.1.140";
  };

  services.flake-lock-sync.enable = lib.mkForce false;
  systemd.timers.flake-lock-sync.enable = false;

  profiles.node.sentry-monitoring.enable = true;

  services.ai-inference.enable = lib.mkForce false;

  boot.kernelPackages =
    inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-x86_64-v3;
  boot.loader.timeout = lib.mkDefault 5;


  # Shared hermes + pi state via NFS (resilient: nofail, automount, soft)
  services.nfs-cluster-mounts = {
    enable = true;
    mountHermes = true;
    mountPi = true;
  };

  # System hardening (Phase 0: Security Baseline)
  # Preset: compatibility (desktop + monitoring)
  nix-mineral = {
    enable = true;
    preset = [ "compatibility" ];
    settings.etc.kicksecure-module-blacklist = false;
  };

  # Fix: nix-mineral sets hidepid=2 on /proc which blocks nfs-idmapd from
  # reading /proc/net/rpc/nfs4.* channels. Add it to the proc group instead.
  systemd.services.nfs-idmapd.serviceConfig.SupplementaryGroups = [ "proc" ];

  # nfs-idmapd needs /var/lib/nfs/rpc_pipefs/nfs to exist (created by nfsd
  # normally, but can race on boot with nix-mineral's hardened /proc).
  systemd.tmpfiles.rules = [ "d /var/lib/nfs/rpc_pipefs/nfs 0755 root root -" ];


  # Resolve gitconfig conflict between NixOS default and nix-mineral
  environment.etc.gitconfig.source = lib.mkForce (pkgs.writeText "gitconfig" ''
    [user]
      name = Jeremy Kroeker
      email = jkroeker@proton.me
  '');

  system.stateVersion = "26.05";
  services.unbound-common.enable = true;

  # nix-mineral breaks DoT (TLS to port 853) — override with plain DNS
  services.unbound.settings.forward-zone = lib.mkForce [
    {
      name = "ts.net.";
      forward-addr = [ "100.100.100.100" "fd7a:115c:a1e0::53" ];
    }
    {
      name = ".";
      forward-addr = [ "1.1.1.1" "1.0.0.1" "8.8.8.8" "8.8.4.4" ];
    }
  ];

}

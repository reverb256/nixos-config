{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
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
    ipAddress = config.networking.cluster.hosts.sentry.ip;
    interfaceName = "eth0";
    wireless.enable = false;
    unbound.enable = true;
    unbound.listenAddress = config.networking.cluster.hosts.sentry.ip;
  };

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
    preset = ["compatibility"];
    settings.etc.kicksecure-module-blacklist = false;
    # Fix: nix-mineral adds bind+nodev+nosuid+noexec over-itself mounts for
    # /etc, /var, /var/lib, /var/log, /home, /root, /srv, /tmp, /var/tmp.
    # On Sentry all these live on the same btrfs @ subvolume as /.
    # The "bind" + "x-initrd.mount" combo causes initrd to bind-mount the
    # initramfs paths over themselves before pivot_root, hiding the real root's
    # content and preventing boot. Disable the entire filesystem hardening.
    # https://github.com/cynicsketch/nix-mineral/issues/11
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

  # Fix: nix-mineral sets hidepid=2 on /proc which blocks nfs-idmapd from
  # reading /proc/net/rpc/nfs4.* channels. Add it to the proc group instead.
  systemd.services.nfs-idmapd.serviceConfig.SupplementaryGroups = ["proc"];

  # nfs-idmapd needs /var/lib/nfs/rpc_pipefs/nfs to exist (created by nfsd
  # normally, but can race on boot with nix-mineral's hardened /proc).
  systemd.tmpfiles.rules = ["d /var/lib/nfs/rpc_pipefs/nfs 0755 root root -"];

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
      forward-addr = ["100.100.100.100" "fd7a:115c:a1e0::53"];
    }
    {
      name = ".";
      forward-addr = ["1.1.1.1" "1.0.0.1" "8.8.8.8" "8.8.4.4"];
    }
  ];

  # System hardening (Phase 1: Cluster Security)
  security.clusterAudit = {
    enable = true;
    enableFirewall = true;
    enableTailscaleSSH = true;
    bindServicesToLocalhost = true;
  };

  environment.systemPackages = with pkgs; [
    nvtopPackages.full
  ];

}

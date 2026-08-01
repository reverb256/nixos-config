{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  portHelpers = import ../../modules/port-helpers.nix {inherit lib;};
  ports = portHelpers.ports;

  k8s = config.networking.cluster.kubernetes.services;
  cluster = config.networking.cluster;
in {
  systemd.tmpfiles.rules = [
    "R /var/lib/etcd - - - - -"
    "d /data/pi 0775 j_kro j_kro -"
  ];

  services = {
    # k3s-cluster config is in configuration.nix (canonical host config)

    keepalived-vip = {
      enable = true;
      vip = cluster.kubernetes.vip;
      interface = "eth0";
      priority = 110;
    };

    gaming-detection.enable = lib.mkForce false;

    nexus-exec.enable = true;



  };

  programs.steam = {
    enable = lib.mkForce false;
    gamescopeSession.enable = lib.mkForce false;
  };

  environment.systemPackages = with pkgs; [
    llama-cpp
    nvtopPackages.full
  ];

  systemd.services.tailscaled.environment = {
    TS_ADVERTISE_ROUTES = "";
    TS_ROUTES = "";
    TS_SSH = "true";
  };


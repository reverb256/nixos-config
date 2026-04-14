{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.k3s-cluster.enable or false;
in
{
  systemd.services.k3s = lib.mkIf cfg {
    serviceConfig.OOMPolicy = lib.mkForce "continue";
  };

  systemd.services.sshd.serviceConfig.OOMPolicy = lib.mkForce "continue";

  systemd.services.NetworkManager.serviceConfig.OOMPolicy = lib.mkForce "continue";

  systemd.services.systemd-logind.serviceConfig.OOMPolicy = lib.mkForce "continue";

  systemd.services.systemd-journald.serviceConfig.OOMPolicy = lib.mkForce "continue";
}

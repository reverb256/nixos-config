{
  config,
  lib,
  ...
}: let
  cfg = config.services.k3s-cluster.enable or false;
in {
  systemd.services = lib.mkIf cfg {
    k3s.serviceConfig.OOMPolicy = lib.mkForce "continue";

    sshd.serviceConfig.OOMPolicy = lib.mkForce "continue";

    NetworkManager.serviceConfig.OOMPolicy = lib.mkForce "continue";

    systemd-logind.serviceConfig.OOMPolicy = lib.mkForce "continue";

    systemd-journald.serviceConfig.OOMPolicy = lib.mkForce "continue";
  };
}

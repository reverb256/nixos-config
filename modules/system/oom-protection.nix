# Critical Service OOM Protection
# Protects essential services from being killed during memory pressure
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
  # Protect container runtime (k3s bundles containerd)
  systemd.services.k3s = lib.mkIf cfg {
    serviceConfig.OOMPolicy = lib.mkForce "continue";
  };

  # CRITICAL: Protect sshd (lose access without this!)
  systemd.services.sshd.serviceConfig.OOMPolicy = lib.mkForce "continue";

  # Protect networking
  systemd.services.NetworkManager.serviceConfig.OOMPolicy = lib.mkForce "continue";

  # Protect systemd-logind (affects user sessions)
  systemd.services.systemd-logind.serviceConfig.OOMPolicy = lib.mkForce "continue";

  # Protect systemd-journald (logging)
  systemd.services.systemd-journald.serviceConfig.OOMPolicy = lib.mkForce "continue";
}

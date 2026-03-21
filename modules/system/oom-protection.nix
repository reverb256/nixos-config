# Critical Service OOM Protection
# Protects essential services from being killed during memory pressure
{ config, lib, pkgs, ... }:
{
  # Protect container runtime (already protected, but ensure it)
  systemd.services.containerd.serviceConfig.OOMPolicy = lib.mkForce "continue";

  # Protect Docker daemon
  systemd.services.docker.serviceConfig.OOMPolicy = lib.mkForce "continue";

  # CRITICAL: Protect kubelet (Kubernetes will stop without this!)
  systemd.services.kubelet.serviceConfig.OOMPolicy = lib.mkForce "continue";

  # CRITICAL: Protect sshd (lose access without this!)
  systemd.services.sshd.serviceConfig.OOMPolicy = lib.mkForce "continue";

  # Protect networking
  systemd.services.NetworkManager.serviceConfig.OOMPolicy = lib.mkForce "continue";

  # Protect systemd-logind (affects user sessions)
  systemd.services.systemd-logind.serviceConfig.OOMPolicy = lib.mkForce "continue";

  # Protect systemd-journald (logging)
  systemd.services.systemd-journald.serviceConfig.OOMPolicy = lib.mkForce "continue";
}

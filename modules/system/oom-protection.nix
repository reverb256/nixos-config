# Critical Service OOM Protection
# Protects essential services AND desktop session from being killed during memory pressure
#
# Issue #295: 2026-07-15 zephyr OOM crash killed niri + alacritty because
# the compositor had no OOM protection. This module:
# 1. Sets OOMPolicy=continue on critical system services (k3s, sshd, etc.)
# 2. Writes oom_score_adj=-500 for desktop session processes via a
#    oneshot service + repeating timer so the kernel de-prioritizes them
#    when oom-killer fires.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.k3s-cluster.enable or false;

  # Desktop processes to protect with oom_score_adj = -500
  protectedDesktopProcesses = [
    "niri"
    "noctalia"
    "spotify"
    "zen-twilight"
    "zen"
    "vesktop"
  ];

  # Build a shell script that sets oom_score_adj for each process
  desktopOomProtectScript = pkgs.writeShellScript "desktop-oom-protect" (
    builtins.concatStringsSep "\n" (map (proc:"
# Protect ${proc}
for pid in \$(pgrep -x ${proc} 2>/dev/null || true); do
  echo -500 > /proc/\$pid/oom_score_adj 2>/dev/null || true
done
") protectedDesktopProcesses)
  );
in {
  # ── System service OOMPolicy ────────────────────────────────────────
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

  # ── Desktop session OOM score protection ────────────────────────────
  # Oneshot service: runs the script to set oom_score_adj for desktop processes
  systemd.services.desktop-oom-protect = {
    description = "Set oom_score_adj=-500 for desktop session processes";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = desktopOomProtectScript;
      # Don't fail if a process isn't running yet
      SuccessExitStatus = [0 1];
    };
    # Only run on hosts with a graphical session
    wantedBy = lib.mkIf config.services.xserver.enable ["graphical-session.target"];

  };

  # Repeating timer: re-apply every 30s to catch newly spawned processes
  systemd.timers.desktop-oom-protect = {
    description = "Periodically protect desktop session from OOM";
    wantedBy = lib.mkIf config.services.xserver.enable ["timers.target"];
    timerConfig = {
      OnBootSec = "10s";
      OnUnitActiveSec = "30s";
      AccuracySec = "5s";
    };
  };
}

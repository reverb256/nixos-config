# Dendritic feature module — converted reference
#
# CANONICAL SKELETON (convention-module-skeleton ticket):
#   - uniform outer head `{ inputs, ... }:` (skeleton Q3 → A)
#   - key = file name verbatim, kebab-case (skeleton Q1 → A)
#   - inner module = OLD BODY VERBATIM (zero body edits; skeleton Q2 → A)
#   - CROSS-FEATURE READ: `config.services.k3s-cluster.enable or false` reads
#     another feature's option. Under host-wiring Q3 → B, the HOST must import
#     BOTH `oom-protection` AND `k3s-cluster` (explicit dependency imports);
#     a host that imports oom-protection without k3s-cluster gets a loud eval
#     error ("option services.k3s-cluster does not exist"), which is the
#     intended failure mode.
{ inputs, ... }: {
  flake.modules.nixos.oom-protection = {
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
      builtins.concatStringsSep "\n" (map (proc: ''
        # Protect ${proc}
        for pid in $(pgrep -x ${proc} 2>/dev/null || true); do
          echo -500 > /proc/$pid/oom_score_adj 2>/dev/null || true
        done
      '') protectedDesktopProcesses)
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
  };
}

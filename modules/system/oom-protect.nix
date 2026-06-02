{
  config,
  pkgs,
  lib,
  ...
}:
# OOM Protection — Mission-Critical Processes
#
# Protects opencode, hermes, claude, and LLM inference from the
# Linux OOM killer by setting negative oom_score_adj values.
#
# These processes are essential for the MapleSpike development
# workflow and should never be OOM-killed.
#
# Imperative: sudo bash -c 'for pid in $(pgrep -f "opencode|hermes|claude|llama-server"); do echo -500 > /proc/$pid/oom_score_adj; done'
# Verify: cat /proc/<pid>/oom_score_adj
let
  # Processes to protect, matched by comm/pid pattern
  protectedProcesses = [
    "opencode"
    "hermes"
    "claude"
    "llama-server"
    "llama-cli"
    "llama.cpp"
  ];

  # OOM score adjustment: -1000 (never kill) to +1000 (always kill first)
  # -500 = strongly protected but not immortal
  # Systemd user services default to 0
  oomScore = "-500";

  # Script that sets OOM protection for matching processes
  oomProtectScript = pkgs.writeShellScriptBin "oom-protect" ''
    set -euo pipefail
    SCORE="${oomScore}"
    for pattern in ${builtins.toString protectedProcesses}; do
      for pid in $(pgrep -f "$pattern" 2>/dev/null || true); do
        CURRENT=$(cat /proc/"$pid"/oom_score_adj 2>/dev/null || echo "")
        if [ "$CURRENT" != "$SCORE" ] && [ -n "$CURRENT" ]; then
          echo "$SCORE" > /proc/"$pid"/oom_score_adj 2>/dev/null || true
        fi
      done
    done
  '';
in {
  environment.systemPackages = [oomProtectScript];

  # Systemd timer: run oom-protect every 30 seconds
  systemd.services.oom-protect = {
    description = "OOM Protection for mission-critical processes";
    after = ["multi-user.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${oomProtectScript}/bin/oom-protect";
      # ProtectHome and other sandboxing would prevent /proc access
      ProtectSystem = false;
      PrivateTmp = false;
    };
  };

  systemd.timers.oom-protect = {
    description = "Periodic OOM protection enforcement";
    timerConfig = {
      OnBootSec = "10s";
      OnUnitActiveSec = "30s";
    };
    wantedBy = ["timers.target"];
  };

  # Global OOM tuning
  boot.kernel.sysctl = {
    # Prefer reclaiming clean pagecache over killing processes
    "vm.overcommit_memory" = lib.mkOverride 90 1;
    # Lower the tendency to OOM-kill (higher = less aggressive)
    # Default: 0 — one-shot. 1 — always overcommit (no OOM for mallocs).
    # We use 1 because we have swap and the LLM needs large allocations.
    "vm.overcommit_ratio" = lib.mkOverride 90 50;
    # Increase swapiness slightly — prefer swapping over killing
    "vm.swappiness" = lib.mkOverride 90 30;
  };

  # Notify user when OOM protection activates
  systemd.services.oom-protect-oneshot = {
    description = "One-time OOM protection at boot";
    after = ["multi-user.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${oomProtectScript}/bin/oom-protect";
      ExecStartPost = "${pkgs.coreutils}/bin/echo 'OOM protection enabled for: ${builtins.toString protectedProcesses}'";
    };
  };
}

#!/usr/bin/env bash
# Imperative peakminer v1.0.11-rc2 cluster launch (bypasses nixos-rebuild).
# Run from zephyr. Stops systemd-managed peakminer units + pkill stragglers
# on all 3 nodes, then imperatively launches /etc/nixos/packages/vendor/peakminer-1.0.11-rc2
# on each of the 5 GPUs with the per-instance config from hosts/*/services.nix.
# Logs/tail to /tmp/peakminer-logs/<user>.{log,stdout} (works without sudo).
set +e
POOL='stratum+tcp://prl.kryptex.network:7048'
VAULT='/etc/nixos/packages/vendor/peakminer-1.0.11-rc2'
LOGDIR=/tmp/peakminer-logs

log() { echo "[launch] $*"; }
ssh_bash() { ssh "$1" /bin/bash; }

# ── kill phase ──────────────────────────────────────────────────────────────
log "Phase 1: stop systemd-managed peakminer (+ pkill any stragglers)"
for h in zephyr forge nexus; do
  ssh "$h" /bin/bash <<'KILLALL'
set +e
sudo systemctl stop peakminer-zephyr-3060ti peakminer-zephyr-3090 \
                       peakminer-forge-4060-0 peakminer-forge-4060-1 \
                       peakminer-nexus-3060ti 2>&1 | head -3
sudo pkill -9 -f peakminer
sleep 2
pgrep -af peakminer 2>/dev/null | head -3 || echo STOPPED
KILLALL
done
# Also local (zephyr host)
sudo systemctl stop peakminer-zephyr-3060ti peakminer-zephyr-3090 2>&1 | head -2
sudo pkill -9 -f peakminer 2>/dev/null || true
sleep 2

# ── zephyr launch ───────────────────────────────────────────────────────────
log "Phase 2: launch v1.0.11-rc2 on zephyr"
ssh zephyr /bin/bash <<ZEOF
set +e
sudo nvidia-smi -i 0 -pl 120 2>&1 | head -1
sudo nvidia-smi -i 1 -pl 250 2>&1 | head -1
sudo mkdir -p $LOGDIR
sudo chmod 777 $LOGDIR
start_pm() {
  local id=\$1 port=\$2 user=\$3 temp=\$4
  export LD_LIBRARY_PATH=/run/opengl-driver/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}
  export CUDA_DEVICE_ORDER=PCI_BUS_ID
  sudo setsid nohup $VAULT \\
    --coin pearl --url $POOL \\
    --user "\$user" --devices "\$id" --api-port "\$port" \\
    --legacy-auth --gpu-temp-stop "\$temp" \\
    --gpu-fan-target 65 --gpu-fan-min 30 --gpu-fan-max 100 \\
    --log-file $LOGDIR/\$user.log --log-append \\
    </dev/null >$LOGDIR/\$user.stdout 2>&1 &
  disown
  echo "launched \$user"
}
start_pm 0 21553 krxXVNVMM7.zephyr-3060ti 80
start_pm 1 21554 krxXVNVMM7.zephyr-3090   80
sleep 5
ps -ef | grep '[p]eakminer' | head -10
ZEOF

# ── forge launch ────────────────────────────────────────────────────────────
log "Phase 3: launch v1.0.11-rc2 on forge"
ssh forge /bin/bash <<FEOF
set +e
sudo systemctl stop peakminer-forge-4060-0 peakminer-forge-4060-1 2>&1 | head -2
sudo pkill -9 -f peakminer
sleep 2
sudo mkdir -p $LOGDIR
sudo chmod 777 $LOGDIR
sudo nvidia-smi -i 0 -pl 118 2>&1 | head -1
sudo nvidia-smi -i 1 -pl 118 2>&1 | head -1
start_pm() {
  local id=\$1 port=\$2 user=\$3 temp=\$4
  export LD_LIBRARY_PATH=/run/opengl-driver/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}
  export CUDA_DEVICE_ORDER=PCI_BUS_ID
  sudo setsid nohup $VAULT \\
    --coin pearl --url $POOL \\
    --user "\$user" --devices "\$id" --api-port "\$port" \\
    --legacy-auth --gpu-temp-stop "\$temp" \\
    --gpu-fan-target 65 --gpu-fan-min 30 --gpu-fan-max 100 \\
    --log-file $LOGDIR/\$user.log --log-append \\
    </dev/null >$LOGDIR/\$user.stdout 2>&1 &
  disown
  echo "launched \$user"
}
start_pm 0 21550 krxXVNVMM7.forge-4060-0 72
start_pm 1 21552 krxXVNVMM7.forge-4060-1 72
sleep 5
ps -ef | grep '[p]eakminer' | head -10
FEOF

# ── nexus launch ────────────────────────────────────────────────────────────
log "Phase 4: launch v1.0.11-rc2 on nexus"
ssh nexus /bin/bash <<NEOF
set +e
sudo systemctl stop peakminer-nexus-3060ti 2>&1 | head -2
sudo pkill -9 -f peakminer
sleep 2
sudo mkdir -p $LOGDIR
sudo chmod 777 $LOGDIR
sudo nvidia-smi -i 0 -pl 120 2>&1 | head -1
start_pm() {
  local id=\$1 port=\$2 user=\$3 temp=\$4
  export LD_LIBRARY_PATH=/run/opengl-driver/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}
  export CUDA_DEVICE_ORDER=PCI_BUS_ID
  sudo setsid nohup $VAULT \\
    --coin pearl --url $POOL \\
    --user "\$user" --devices "\$id" --api-port "\$port" \\
    --legacy-auth --gpu-temp-stop "\$temp" \\
    --gpu-fan-target 65 --gpu-fan-min 30 --gpu-fan-max 100 \\
    --log-file $LOGDIR/\$user.log --log-append \\
    </dev/null >$LOGDIR/\$user.stdout 2>&1 &
  disown
  echo "launched \$user"
}
start_pm 0 21551 krxXVNVMM7.nexus-3060ti 72
sleep 5
ps -ef | grep '[p]eakminer' | head -10
NEOF

# ── verification ────────────────────────────────────────────────────────────
sleep 6
echo "==== /summary verification ===="
for entry in zephyr:21553 zephyr:21554 forge:21550 forge:21552 nexus:21551; do
  h="\${entry%:*}"; p="\${entry##*:}"
  echo "--- \$h:\$p ---"
  ssh "\$h" "curl -sf --max-time 4 http://127.0.0.1:\$p/summary 2>/dev/null | head -c 400"
  echo
done
echo "==== DONE ===="

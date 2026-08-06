# GPU readiness service.
#
# Waits for DRM/GPU devices to be ready before the display manager starts,
# preventing the boot race where SDDM/niri autologin fires before the NVIDIA
# or AMD driver has initialized. NOT Plasma-specific: also needed on niri
# hosts (sddm autologin into niri-uwsm), so this module is loaded
# unconditionally on every host that reaches a display-manager target.
{ pkgs, lib, ... }: {
  systemd.services.gpu-ready = {
    description = "Wait for GPU devices to be ready";
    after = ["systemd-modules-load.service"];
    wantedBy = ["display-manager.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "gpu-ready" ''
        # Wait for GPU DRM devices to be ready (NVIDIA/CUDA or AMD/ROCm)
        # NVIDIA: /proc/driver/nvidia, /dev/nvidiactl
        # AMD: /sys/class/drm/card*/device/vendor (0x1002 = AMD)
        log() {
          echo "[gpu-ready] $1" >&2
        }
        # Check if any DRM device exists and is accessible
        check_drm_devices() {
          for dev in /dev/dri/card*; do
            if [ -e "$dev" ] && [ -r "$dev" ]; then
              return 0
            fi
          done
          return 1
        }
        # Check for NVIDIA GPUs (CUDA)
        has_nvidia() {
          [ -d /proc/driver/nvidia ] && [ -e /dev/nvidiactl ]
        }
        # Check for AMD GPUs (ROCm)
        has_amd() {
          [ -d /sys/class/drm ] && grep -q "0x1002" /sys/class/drm/card*/device/vendor 2>/dev/null
        }
        # Wait for NVIDIA driver to fully load
        wait_nvidia() {
          local max_attempts=30
          for i in $(seq 1 $max_attempts); do
            if [ -e /dev/nvidiactl ] && [ -r /dev/nvidiactl ]; then
              return 0
            fi
            sleep 0.5
          done
          return 1
        }
        DETECTED_GPUS=""
        has_nvidia && {
          DETECTED_GPUS="$DETECTED_GPUS NVIDIA(CUDA)"
          log "Waiting for NVIDIA driver to fully initialize..."
          wait_nvidia || log "WARNING: NVIDIA driver may not be fully initialized"
        }
        has_amd && DETECTED_GPUS="$DETECTED_GPUS AMD(ROCm)"
        if [ -n "$DETECTED_GPUS" ]; then
          log "Detected GPUs:$DETECTED_GPUS"
        else
          log "No GPUs detected, waiting for DRM devices..."
        fi
        # Wait up to 15 seconds for DRM devices to be accessible
        for i in $(seq 1 75); do
          if check_drm_devices; then
            log "DRM devices ready at /dev/dri/"
            ls -la /dev/dri/card* 2>/dev/null || true
            exit 0
          fi
          sleep 0.2
        done
        # Timeout - log warning but proceed (display manager has restart logic)
        log "WARNING: Timeout waiting for DRM devices, proceeding anyway"
        exit 0
      '';
    };
  };
}

{
  pkgs,
  config,
  lib,
  ...
}: let
  # GPU Tuning ConfigMap with per-card, per-algorithm settings
  # Applied inside privileged container via nvidia-smi before miner starts
in {
  config.kubernetes.objects = {
    mining.ConfigMap.gpu-tune-script = {
      data."gpu-tune.sh" = ''
        #!/bin/sh
        # GPU Tuning Script for Mining
        # Applies clock/power/fan settings based on algorithm and GPU profile
        set -e

        DEVICE="''${DEVICE_INDEX:-0}"
        GPU_PROFILE="''${GPU_PROFILE:-rtx4060}"
        MINER_TYPE="''${MINER_TYPE:-rigel}"
        ALGO="''${1:-kawpow}"

        echo "[gpu-tune] Applying tuning for $GPU_PROFILE algo=$ALGO device=$DEVICE"

        if [ "$MINER_TYPE" = "teamredminer" ]; then
            echo "[gpu-tune] AMD tuning applied via teamredminer --set flags"
            exit 0
        fi

        # Find nvidia-smi
        NVIDIA_SMI=$(which nvidia-smi 2>/dev/null || find /nix/store -name nvidia-smi -type f 2>/dev/null | head -1)

        if [ -z "$NVIDIA_SMI" ]; then
            echo "[gpu-tune] WARNING: nvidia-smi not found, skipping GPU tuning"
            exit 0
        fi

        echo "[gpu-tune] Using nvidia-smi: $NVIDIA_SMI"

        # Per-profile, per-algorithm tuning table
        # Power(W), CoreOffset(MHz), MemOffset(MHz), Fan(%)
        case "$GPU_PROFILE" in
            rtx4060)
                case "$ALGO" in
                    kawpow)      POWER=100; CORE=200;  MEM=400;  FAN=80 ;;
                    octopus)     POWER=90;  CORE=-200; MEM=800;  FAN=75 ;;
                    autolykos2)  POWER=95;  CORE=50;   MEM=500;  FAN=75 ;;
                    nexapow)     POWER=105; CORE=200;  MEM=200;  FAN=80 ;;
                    fishhash)    POWER=90;  CORE=-100; MEM=800;  FAN=75 ;;
                    xelishashv3) POWER=95;  CORE=50;   MEM=500;  FAN=75 ;;
                    *)           POWER=95;  CORE=0;    MEM=0;    FAN=75 ;;
                esac ;;
            rtx3060ti)
                case "$ALGO" in
                    kawpow)      POWER=130; CORE=150;  MEM=600;  FAN=80 ;;
                    octopus)     POWER=120; CORE=-200; MEM=800;  FAN=75 ;;
                    autolykos2)  POWER=125; CORE=50;   MEM=600;  FAN=75 ;;
                    nexapow)     POWER=140; CORE=200;  MEM=300;  FAN=80 ;;
                    fishhash)    POWER=120; CORE=-100; MEM=800;  FAN=75 ;;
                    xelishashv3) POWER=125; CORE=50;   MEM=600;  FAN=75 ;;
                    *)           POWER=130; CORE=0;    MEM=0;    FAN=75 ;;
                esac ;;
            rtx3090)
                case "$ALGO" in
                    kawpow)      POWER=240; CORE=100;  MEM=800;  FAN=85 ;;
                    octopus)     POWER=220; CORE=-200; MEM=1200; FAN=90 ;;
                    autolykos2)  POWER=230; CORE=50;   MEM=800;  FAN=85 ;;
                    nexapow)     POWER=260; CORE=200;  MEM=400;  FAN=90 ;;
                    fishhash)    POWER=220; CORE=-100; MEM=1200; FAN=90 ;;
                    xelishashv3) POWER=230; CORE=50;   MEM=800;  FAN=85 ;;
                    *)           POWER=250; CORE=0;    MEM=0;    FAN=85 ;;
                esac ;;
            *)
                echo "[gpu-tune] Unknown GPU profile: $GPU_PROFILE"
                POWER=100; CORE=0; MEM=0; FAN=75 ;;
        esac

        echo "[gpu-tune] Settings: power=''${POWER}W core_offset=''${CORE}MHz mem_offset=''${MEM}MHz fan=''${FAN}%"

        # Apply power limit
        $NVIDIA_SMI -i $DEVICE -pl $POWER 2>/dev/null && \
            echo "[gpu-tune] Power limit: ''${POWER}W" || \
            echo "[gpu-tune] WARNING: Failed to set power limit"

        # Reset clocks
        $NVIDIA_SMI -i $DEVICE -rgc 2>/dev/null || true
        $NVIDIA_SMI -i $DEVICE -rmc 2>/dev/null || true

        # Apply clock offsets
        if [ "$CORE" -ne 0 ] 2>/dev/null; then
            $NVIDIA_SMI -i $DEVICE --gpu-clock-offset=$CORE 2>/dev/null && \
                echo "[gpu-tune] Core offset: ''${CORE}MHz" || \
                echo "[gpu-tune] WARNING: Failed to set core clock offset"
        fi

        if [ "$MEM" -ne 0 ] 2>/dev/null; then
            $NVIDIA_SMI -i $DEVICE --memory-clock-offset=$MEM 2>/dev/null && \
                echo "[gpu-tune] Mem offset: ''${MEM}MHz" || \
                echo "[gpu-tune] WARNING: Failed to set mem clock offset"
        fi

        echo "[gpu-tune] Tuning complete for device $DEVICE"
      '';
    };
  };
}

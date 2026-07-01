#!/usr/bin/env bash
# PeakMiner Launch Script - Declarative version
#
# This script is installed by NixOS and manages PeakMiner instances
# Auth-format translation proxy is also started for Kryptex pools

set -e

HOSTNAME=$(hostname)

case "$HOSTNAME" in
  zephyr)
    # GPU 0: 3060Ti
    # GPU 1: 3090 hybrid (fan 0% is normal)
    nvidia-smi -i 0 -pl 100
    nvidia-smi -i 1 -pl 250

    # Start auth-translator proxy for GPU 0
    python3 /etc/nixos/pkgs/stratum-auth-translator.py --proxy-port 21550 &
    PROXY_PID_0=$!

    # Start PeakMiner GPU 0
    export CUDA_VISIBLE_DEVICES=0
    export CUDA_DEVICE_ORDER=PCI_BUS_ID
    export LD_LIBRARY_PATH=/run/opengl-driver/lib
    /run/current-system/sw/bin/peakminer \
      --wallet krxXVNVMM7 \
      --pool stratum+tcp://prl.kryptex.network:7048 \
      --device 0 \
      --api "0.0.0.0:21553" \
      --no-watchdog &

    # Start auth-translator proxy for GPU 1
    python3 /etc/nixos/pkgs/stratum-auth-translator.py --proxy-port 21551 &
    PROXY_PID_1=$!

    # Start PeakMiner GPU 1
    export CUDA_VISIBLE_DEVICES=1
    /run/current-system/sw/bin/peakminer \
      --wallet krxXVNVMM7 \
      --pool stratum+tcp://prl.kryptex.network:7048 \
      --device 0 \
      --api "0.0.0.0:21554" \
      --no-watchdog &

    # Cleanup function
    cleanup() {
      kill $PROXY_PID_0 $PROXY_PID_1 2>/dev/null
    }
    trap cleanup EXIT

    wait
    ;;

  forge)
    # GPU 0: 4060
    # GPU 1: 4060
    nvidia-smi -i 0 -pl 110
    nvidia-smi -i 1 -pl 110

    # Start auth-translator proxy for GPU 0
    python3 /etc/nixos/pkgs/stratum-auth-translator.py --proxy-port 21552 &
    PROXY_PID_0=$!

    # Start PeakMiner GPU 0
    export CUDA_VISIBLE_DEVICES=0
    export CUDA_DEVICE_ORDER=PCI_BUS_ID
    export LD_LIBRARY_PATH=/run/opengl-driver/lib
    /run/current-system/sw/bin/peakminer \
      --wallet krxXVNVMM7 \
      --pool stratum+tcp://prl.kryptex.network:7048 \
      --device 0 \
      --api "0.0.0.0:21550" \
      --no-watchdog &

    # Start auth-translator proxy for GPU 1
    python3 /etc/nixos/pkgs/stratum-auth-translator.py --proxy-port 21553 &
    PROXY_PID_1=$!

    # Start PeakMiner GPU 1
    export CUDA_VISIBLE_DEVICES=1
    /run/current-system/sw/bin/peakminer \
      --wallet krxXVNVMM7 \
      --pool stratum+tcp://prl.kryptex.network:7048 \
      --device 0 \
      --api "0.0.0.0:21551" \
      --no-watchdog &

    # Cleanup function
    cleanup() {
      kill $PROXY_PID_0 $PROXY_PID_1 2>/dev/null
    }
    trap cleanup EXIT

    wait
    ;;

  nexus)
    # GPU 0: 3060Ti
    nvidia-smi -i 0 -pl 120

    # Start auth-translator proxy for GPU 0
    python3 /etc/nixos/pkgs/stratum-auth-translator.py --proxy-port 21542 &
    PROXY_PID_0=$!

    # Start PeakMiner GPU 0
    export CUDA_VISIBLE_DEVICES=0
    export CUDA_DEVICE_ORDER=PCI_BUS_ID
    export LD_LIBRARY_PATH=/run/opengl-driver/lib
    /run/current-system/sw/bin/peakminer \
      --wallet krxXVNVMM7 \
      --pool stratum+tcp://prl.kryptex.network:7048 \
      --device 0 \
      --api "0.0.0.0:21551" \
      --no-watchdog &

    # Cleanup function
    cleanup() {
      kill $PROXY_PID_0 2>/dev/null
    }
    trap cleanup EXIT

    wait
    ;;

  *)
    echo "Unknown hostname: $HOSTNAME"
    exit 1
    ;;
esac
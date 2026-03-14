# Forge Host Configuration - GPU Mining Rig
# 10.1.1.130 - 6 cores, 2x RTX 4060 + 2x RX 5700 XT
# Features: Mining only (no gaming/VR), ROCm + CUDA
#
# Module imports: Gaming, mining, monitoring, opencode are already imported
# via commonModules in flake.nix (./modules/default.nix)
# Note: Gaming module imported globally but gaming.enable=false for this host
{
  lib,
  pkgs,
  ...
}: {
  imports = [
    # Monitoring configuration
    ./monitoring.nix
    # Hardware configuration (generated)
    ./hardware-configuration.nix

    # All other modules (desktop, networking, services, etc.)
    ../../modules/default.nix

    # GPU support (wayland-specific, host-dependent)
    ../../modules/hardware/nvidia-common.nix
    ../../modules/hardware/nvidia-wayland.nix
    ../../modules/hardware/amdgpu-wayland.nix
    ../../modules/hardware/rgb-control.nix
    ../../modules/system/security.nix
    ../../modules/services/podman-support.nix

    # Kubernetes worker node (opt-in)
    ../../modules/services/kubernetes.nix
  ];

  # ============================================================================
  # NETWORKING CONFIGURATION
  # ============================================================================
  # Centralized cluster networking (search domains, DNS, firewall basics)
  clusterNetworking = {
    enable = true;
    hostName = "forge";
    ipAddress = "10.1.1.130";
    interfaceName = "enp0s31f6"; # Native hardware interface name
    wireless.enable = false; # Mining rig - no WiFi needed
    unbound.listenAddress = "10.1.1.130"; # Listen on node IP for cluster DNS
  };

  # Populate /etc/hosts from central cluster configuration
  networking = {
    cluster-hosts = {
      enable = true;
      populateLocal = true;
    };

    # Forge-specific firewall rules (in addition to cluster defaults)
    firewall = {
      allowedTCPPorts = lib.mkOptionDefault [
        10250 # Kubelet API
      ];
      allowedTCPPortRanges = [
        {
          from = 30000;
          to = 32767;
        }
      ];
      allowedUDPPorts = lib.mkOptionDefault [
        8472 # Flannel VXLAN
      ];
    };
  };

  # ============================================================================
  # NODE PROFILE - Platform-level defaults
  # ============================================================================
  # This profile bundles role profiles, Kubernetes config, hardware profiles,
  # and networking configuration. Eliminates ~100 lines of duplication.
  profiles.node.forge-mining.enable = true;

  # ============================================================================
  # SERVICES CONFIGURATION
  # ============================================================================
  services = {
    # Crash detection and logging
    crash-watchdog.enable = true;

    # Kubernetes worker configuration provided by node-profiles.forge-mining
    # No need to duplicate here

    # Spotify with SpotX patch (ad-free, premium features)
    spotify-spotx.enable = true;

    # OpenCode - AI coding assistant configuration
    opencode.enable = true;

    # Mount /etc/nixos from zephyr (single-source-of-truth)
    nixos-share = {
      enable = true;
      client.enable = true;
    };

    # Mining configuration - lolminer for NVIDIA and AMD GPUs
    mining.lolminer = {
      # NVIDIA GPUs (2x RTX 4060) - devices 2,3 in lolminer's combined enumeration
      # (AMD GPUs are 0,1, NVIDIA GPUs are 2,3 when both OpenCL and CUDA are available)
      nvidia = {
        enable = true;
        autostart = true;
        devices = "2,3";
        powerLimit = 90;
        apiPort = 4068;
      };

      # AMD GPUs (RX 5700 XT) - OpenCL devices 0,1
      # Note: PCI addresses 03:00.0 and 08:00.0, but OpenCL numbers from 0
      amd = {
        enable = true;
        autostart = true;
        devices = "0,1";
        powerLimit = 140;
        apiPort = 4069;
      };

      # GPU miners connect to gpu-proxy first, fallback to Kryptex
      # Multi-pool failover: nexus proxy first, then direct Kryptex
      pool = "xtm-c29-us.kryptex.network:8040";  # Fallback if pools list empty
      wallet = "krxXVNVMM7.forge-gpu";
      pools = [
        {
          url = "10.1.1.120:3334";  # gpu-proxy on Nexus (primary)
          wallet = "krxXVNVMM7.forge-gpu";
          password = "x";
          tls = false;  # No TLS for local proxy
        }
        {
          url = "xtm-c29-us.kryptex.network:8040";  # Direct Kryptex (fallback)
          wallet = "krxXVNVMM7.forge-gpu";
          password = "x";
          tls = true;  # TLS required for Kryptex
        }
      ];
    };

    # GPU Stratum Proxy with Kryptex pool failover
    # DISABLED: Now using gpu-proxy on Nexus
    gpu-proxy = {
      enable = false;
      listenPort = 3334;
      apiPort = 8083;
      logLevel = "INFO";
      pools = [
        {
          name = "Kryptex US";
          url = "stratum+tcp://xtm-c29-us.kryptex.network:8040";
          wallet = "krxXVNVMM7";
          password = "x";
          priority = 1;
          tls = true;
        }
        {
          name = "Kryptex EU";
          url = "stratum+tcp://xtm-c29-eu.kryptex.network:8040";
          wallet = "krxXVNVMM7";
          password = "x";
          priority = 2;
          tls = true;
        }
      ];
      workers = [
        {
          id = "forge-gpu";
          password = "x";
        }
      ];
      openFirewall = false;
    };

    # NFS Client - Mount shared storage from nexus
    nfs-client = {
      enable = true;
      mountShared = true;
      mountHome = true;
      mountMedia = true;
    };

    # Syncthing P2P file sync for /etc/nixos config sync
    syncthing-cluster = {
      enable = true;
      deviceId = "FORGE-PLACEHOLDER";
    };
  };

  # ============================================================================
  # HARDWARE PROFILES
  # ============================================================================
  # Base profiles provided by node-profiles.forge-mining:
  # - intel, nvidia.enable (multiGpu), amdgpu.enable, amdgpu.wayland, monitoring.enable
  #
  # Forge-specific hardware additions:
  hardware = {
    # NVIDIA GPU support (base driver)
    nvidia-common.enable = true;

    # BTRFS compression and deduplication
    btrfs-compression.enable = true;

    # Hardware monitoring (lm-sensors for CPU/motherboard temps)
    monitoring = {
      enable = true;
      autoDetect = true; # Auto-detect sensor chips
      fanControl = false; # BIOS fan control for now
    };

    # RGB control for ASRock RX 5700 XT and motherboard
    rgb-control = {
      enable = true;
      openrgb.enable = true;
      temperatureReactive = {
        enable = true;
        sensor = "gpu"; # Monitor GPU temps for mining
        thresholds = {
          cool = 60;
          warm = 70;
          hot = 75;
        };
        interval = 10; # Poll every 10 seconds
      };
    };
  };

  # ============================================================================
  # ROLE PROFILES
  # ============================================================================
  # Base role profiles provided by node-profiles.forge-mining:
  # - mining, aiInference
  # Kubernetes and networking also handled by node profile
  #
  # No additional role profiles needed - all handled by node profile

  # ============================================================================
  # NETWORK PROFILES
  # ============================================================================
  # Base Tailscale configuration provided by node-profiles.forge-mining
  # No additional network profile configuration needed

  # ============================================================================
  # BOOT CONFIGURATION
  # ============================================================================
  # Base bootloader settings provided by common-host-defaults.nix:
  # - systemd-boot.enable, efi.canTouchEfiVariables, kernelPackages (linux_zen)
  #
  # Only add Forge-specific kernel parameters here that aren't provided by modules
  boot = {
    # KERNEL PARAMETERS
    # NOTE: Most parameters provided by shared modules:
    # - kernel-hardening.nix: quiet, splash, loglevel=3, lsm stack, zswap, etc.
    # - nvidia-wayland.nix: nvidia-drm.modeset=1
    # - profiles/hardware/implementations.nix: intel_iommu=on, iommu=pt (Intel)
    # - mining.nix: hugepagesz=1G, hugepages=3 (when mining enabled)
    #
    # Only add Forge-specific parameters here that aren't provided by modules
    kernelParams = [
      # No overrides needed - using hardened defaults from kernel-hardening.nix
      # Previously had loglevel=4 and reduced lsm stack which weakened security
    ];

    # GPU DRIVERS (Hybrid AMD + NVIDIA)
    # Note: NVIDIA modules loaded via nvidia-wayland.nix
    # Note: AMDGPU loaded via hardware.profiles.amdgpu.wayland (initrd too)
    kernelModules = ["tun"]; # amdgpu added by profile, not duplicated here
  };

  # ============================================================================
  # MINING CONFIGURATION (Forge: 6 cores, 2x RTX 4060 + 2x RX 5700 XT)
  # ============================================================================
  # Note: profiles.role.mining enables services.mining automatically
  # Mining configuration moved to services block above

  # ============================================================================
  # AMD GPU POWER MANAGEMENT
  # RX 5700 XT power limit set to 140W for stability and thermal management
  # Uses direct sysfs interface (more reliable than rocm-smi)
  # ============================================================================
  # Set RTX 4060s to EXCLUSIVE_PROCESS mode for compute/mining only
  # Prevents graphics/display usage, reduces interference with mining
  # Smooth fan curve for RX 5700 XT to prevent spiking
  # - Temperature-based targeting with hysteresis
  # - Dead zones to prevent rapid oscillation
  # - Gradual ramp changes
  # ============================================================================
  systemd = {
    services = {
      amd-gpu-power-mgmt = {
        description = "AMD GPU Power Limit (140W for RX 5700 XT)";
        wantedBy = ["multi-user.target"];
        after = ["basic.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "amd-power-limit" ''
            #!/usr/bin/env bash
            set -euo pipefail

            POWER_LIMIT_MICROWATTS=140000000  # 140W in microwatts

            log() {
              echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
            }

            # Wait for GPUs to be ready
            sleep 5

            # Set power limit for all AMD GPUs via sysfs
            for card in /sys/class/drm/card*/device/hwmon/hwmon*/power1_cap; do
              if [[ -w "$card" ]]; then
                card_name=$(basename $(dirname $(dirname $(dirname "$card"))))
                echo "$POWER_LIMIT_MICROWATTS" > "$card"
                actual=$(cat "$card")
                watts=$((actual / 1000000))
                log "AMD GPU $card_name: Power limit set to ''${watts}W"
              fi
            done

            log "AMD GPU power management configured"
          '';
        };
      };

      nvidia-compute-mode = {
        description = "NVIDIA GPU Compute-Only Mode (EXCLUSIVE_PROCESS)";
        wantedBy = ["multi-user.target"];
        after = ["basic.target"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "nvidia-compute-mode" ''
            #!/usr/bin/env bash
            set -euo pipefail

            log() {
              echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
            }

            # Wait for NVIDIA driver to be ready
            for i in {1..30}; do
              if /run/current-system/sw/bin/nvidia-smi &>/dev/null; then
                log "NVIDIA driver ready"
                break
              fi
              log "Waiting for NVIDIA driver... ($i/30)"
              sleep 2
            done

            # Set compute mode for all NVIDIA GPUs
            # EXCLUSIVE_PROCESS (3): Only one compute process can use each GPU
            /run/current-system/sw/bin/nvidia-smi -c 3

            # Verify the setting
            /run/current-system/sw/bin/nvidia-smi --query-gpu=name,compute_mode --format=csv,noheader | while IFS=, read -r name mode; do
              log "NVIDIA GPU ''${name// /}: Compute mode = ''${mode// /}"
            done

            log "NVIDIA GPUs set to compute-only mode"
          '';
        };
      };

      amd-gpu-fan-curve = {
        description = "AMD GPU Dynamic Fan Curve Control";
        # FIXED: awk escaping bug resolved by using bc instead of awk
        wantedBy = ["multi-user.target"];
        after = ["network.target" "amd-gpu-power-mgmt.service"];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "10s";
          ExecStart = pkgs.writeShellScript "amd-fan-curve" ''
            #!/run/current-system/sw/bin/bash
            set -euo pipefail

            PATH=/run/current-system/sw/bin:$PATH

            # Fan curve configuration (RX 5700 XT optimized)
            # Format: "TEMP:TARGET_FAN_SPEED"
            # Temp in Celsius, fan speed as percentage (0-100)
            # Balanced curve - max 80% to reduce noise while keeping temps reasonable
            # Note: AMD driver may still override to 100% if junction temp hits ~70°C
            FAN_CURVE=(
              "50:50"   # 50°C -> 50% (quiet operation)
              "55:60"   # 55°C -> 60%
              "60:70"   # 60°C -> 70%
              "65:80"   # 65°C -> 80% (max fan speed - noise limit)
              "70:80"   # 70°C -> 80% (at driver threshold - will likely override)
              "75:80"   # 75°C -> 80%
            )

            # Hysteresis configuration (prevents rapid oscillation)
            # Only change fan speed if temperature changes by this many degrees
            HYSTERESIS=3

            # Minimum time between fan adjustments (seconds)
            # Prevents rapid successive changes
            MIN_ADJUST_INTERVAL=5

            # State tracking per GPU
            declare -A LAST_TEMP
            declare -A LAST_FAN
            declare -A LAST_ADJUST_TIME

            log() {
              echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
            }

            # GPU to hwmon mapping (bypass rocm-smi which gets overridden by driver)
            declare -A GPU_HWMON
            GPU_HWMON[0]="/sys/class/drm/card0/device/hwmon/hwmon0"
            GPU_HWMON[1]="/sys/class/drm/card1/device/hwmon/hwmon1"

            get_temp() {
              local gpu=$1
              local hwmon="''${GPU_HWMON[$gpu]}"
              # Read junction temperature from temp2_input (millidegrees Celsius)
              local temp_milli=$(cat "$hwmon/temp2_input" 2>/dev/null || echo "0")
              # Use bc for floating point division (more reliable than awk escaping)
              echo "scale=1; $temp_milli / 1000" | bc
            }

            get_target_fan() {
              local temp=$1
              local target_fan=30

              for entry in "''${FAN_CURVE[@]}"; do
                local curve_temp="''${entry%%:*}"
                local curve_fan="''${entry##*:}"

                if (( $(awk "BEGIN {print ($temp >= $curve_temp)}") )); then
                  target_fan=$curve_fan
                fi
              done

              echo "$target_fan"
            }

            set_fan() {
              local fan_pct=$1
              local gpu=$2
              local hwmon="''${GPU_HWMON[$gpu]}"
              # Convert percentage to 0-255 range
              local fan_value=$((fan_pct * 255 / 100))

              # Set manual mode and fan speed via sysfs (direct hardware control)
              if echo "1" > "$hwmon/pwm1_enable" 2>/dev/null && echo "$fan_value" > "$hwmon/pwm1" 2>/dev/null; then
                log "GPU$gpu: Set pwm to $fan_value ($fan_pct%)"
              else
                log "GPU$gpu: Failed to set pwm!"
              fi
            }

            calculate_fan() {
              local temp=$1
              local last_temp=$2
              local last_fan=$3

              local target_fan=$(get_target_fan "$temp")

              # Apply hysteresis - only change if temp moved significantly
              local temp_diff=$(awk "BEGIN {print $temp - $last_temp}")
              local abs_diff=$(awk "BEGIN {if ($temp_diff < 0) print (0 - $temp_diff); else print $temp_diff}")

              if (( $(awk "BEGIN {print ($abs_diff < $HYSTERESIS)}") )); then
                # Within hysteresis zone - keep last fan speed
                echo "$last_fan"
                return
              fi

              # Calculate smoothed fan change (gradual ramp)
              # Higher max_change when temps are high to prevent driver override
              local fan_diff=$((target_fan - last_fan))
              local max_change=25  # Max 25% change per adjustment (increased for thermal safety)

              if (( fan_diff > 0 )); then
                # Ramping up
                if (( fan_diff > max_change )); then
                  echo $((last_fan + max_change))
                else
                  echo "$target_fan"
                fi
              else
                # Ramping down
                local neg_max_change=$((-max_change))
                if (( fan_diff < neg_max_change )); then
                  echo $((last_fan - max_change))
                else
                  echo "$target_fan"
                fi
              fi
            }

            log "Starting temperature-based fan control for RX 5700 XT (devices 0,1)"
            log "Fan curve with hysteresis: ''${HYSTERESIS}°C dead zone, ''${MIN_ADJUST_INTERVAL}s min interval"

            # Initialize with current temps
            for gpu in 0 1; do
              temp=$(get_temp $gpu)
              if [[ -n "$temp" ]]; then
                LAST_TEMP[$gpu]=$temp
                LAST_FAN[$gpu]=$(get_target_fan "$temp")
                LAST_ADJUST_TIME[$gpu]=0
                log "GPU$gpu initial: ''${temp}°C -> fan set to ''${LAST_FAN[$gpu]}%"
                set_fan "''${LAST_FAN[$gpu]}" $gpu
              fi
            done

            sleep 3

            # Main control loop
            while true; do
              current_time=$(date +%s)

              for gpu in 0 1; do
                temp=$(get_temp $gpu)

                if [[ -z "$temp" ]]; then
                  continue
                fi

                # Check if enough time has passed since last adjustment
                time_since_last=$((current_time - LAST_ADJUST_TIME[$gpu]))

                if (( time_since_last >= MIN_ADJUST_INTERVAL )); then
                  new_fan=$(calculate_fan "$temp" "''${LAST_TEMP[$gpu]}" "''${LAST_FAN[$gpu]}")

                  # Update fan speed if changed significantly (>= 5%)
                  fan_change=$((new_fan - LAST_FAN[$gpu]))
                  if (( fan_change >= 5 || fan_change <= -5 )); then
                    log "GPU$gpu: ''${temp}°C (was ''${LAST_TEMP[$gpu]}°C) -> fan ''${new_fan}% (was ''${LAST_FAN[$gpu]}%)"
                    LAST_FAN[$gpu]=$new_fan
                    LAST_TEMP[$gpu]=$temp
                    LAST_ADJUST_TIME[$gpu]=$current_time
                  else
                    # Update temp tracker even if we don't change fan target
                    LAST_TEMP[$gpu]=$temp
                  fi

                  # ALWAYS write PWM to fight driver overrides (every 5s min)
                  set_fan "''${LAST_FAN[$gpu]}" $gpu
                fi
              done

              sleep 2
            done
          '';
        };
      };

      # AMD GPU HEALTH CHECKS
      "amd-gpu-check" = {
        description = "AMD GPU Detection and Health Check";
        wantedBy = ["multi-user.target"];
        after = ["basic.target"];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.bash}/bin/bash -c 'PATH=/run/current-system/sw/bin:$PATH /run/wrappers/bin/sudo rocminfo 2>/dev/null || echo \"AMD GPU detection failed\"'";
          RemainAfterExit = true;
        };
      };

      # AMD GPU MAX FAN SPEED (Simple oneshot - sets 100% at boot)
      # DISABLED: Fan curve service now works and provides better thermal management
      # This can be re-enabled if fan curve has issues
      "amd-gpu-max-fan" = {
        description = "AMD GPU Max Fan Speed (100%) - DISABLED, using fan curve instead";
        # wantedBy = ["multi-user.target"];  # DISABLED
        after = ["basic.target" "amd-gpu-power-mgmt.service"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = pkgs.writeShellScript "amd-max-fan" ''
            #!/usr/bin/env bash
            set -euo pipefail

            log() {
              echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
            }

            # Wait for GPUs to be ready
            sleep 5

            # Set both GPUs to 100% fan speed using rocm-smi
            # This is the reliable method that doesn't require sysfs PWM manipulation
            if /run/wrappers/bin/sudo /run/current-system/sw/bin/rocm-smi --setfan 100%; then
              log "AMD GPUs set to 100% fan speed"
            else
              log "Failed to set AMD GPU fan speed"
            fi
          '';
        };
      };

      "amd-gpu-info" = {
        description = "AMD GPU Information Service";
        wantedBy = ["multi-user.target"];
        after = ["basic.target"];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.bash}/bin/bash -c 'PATH=/run/current-system/sw/bin:$PATH /run/wrappers/bin/sudo rocminfo > /tmp/amd-gpu-info.log 2>&1 || true'";
          RemainAfterExit = true;
        };
      };
    };

    tmpfiles.rules = let
      rocmEnv = pkgs.symlinkJoin {
        name = "rocm-combined";
        paths = with pkgs.rocmPackages; [
          clr
          clr.icd
          rocblas
          hipblas
          rpp
        ];
      };
    in [
      "c /dev/net/tun 666 root root - - - -"
      "L+ /opt/rocm - - - - ${rocmEnv}"
      "L+ /opt/rocm/hip - - - - ${pkgs.rocmPackages.clr}"
      # lolMiner workaround for OpenCL ICD path bug
      "L /etc/OpenCL/vendorsamdocl64.icd - - - - /etc/OpenCL/vendors/amdocl64.icd"
    ];

    slices.mining = {
      description = "Mining Services Slice";
      sliceConfig = {
        CPUAccounting = true;
        # CPU quota managed dynamically by compute-workload-monitor when enabled
        # Without it, mining can use all available CPU (limited by process-level settings)
        # CPUQuota = "95%";  # Uncomment to limit CPU to 95% (conflicts with compute-workload-monitor)
        MemoryAccounting = true;
        MemoryHigh = "8G";
        MemoryMax = "12G";
        IOAccounting = true;
        IOWeight = 10;
        TasksAccounting = true;
        TasksMax = 100;
        BlockIOAccounting = true;
      };
    };
  };

  # ============================================================================
  # ROCm SETUP
  # ============================================================================
  # Note: hardware.profiles.amdgpu.wayland sets ROC_ENABLE_PRE_VEGA=1 automatically
  environment = {
    variables = {
      LD_LIBRARY_PATH = lib.mkForce "${pkgs.rocmPackages.clr}/lib:${pkgs.rocmPackages.clr.icd}/lib:${pkgs.mesa.opencl}/lib";
      OCL_ICD_VENDORS = "/etc/OpenCL/vendors";
    };

    # OpenCL ICD setup for AMD GPUs (lolminer needs this to detect AMD GPUs)
    etc."OpenCL/vendors/amdocl64.icd".source = "${pkgs.rocmPackages.clr.icd}/etc/OpenCL/vendors/amdocl64.icd";

    systemPackages = with pkgs; [
      rocmPackages.rocm-smi
      clinfo # For debugging OpenCL
      opencode # AI coding agent (migrated from nix profile)
    ];
  };

  # ============================================================================
  # NIX-LD (For mining software compatibility)
  # ============================================================================
  programs = {
    nix-ld.enable = true;
    nix-ld.libraries = with pkgs; [
      # AMD/ROCm libraries
      rocmPackages.clr
      rocmPackages.clr.icd
      rocmPackages.rocminfo
      rocmPackages.rocm-smi
      rocmPackages.rocm-runtime
      rocmPackages.rocblas
      rocmPackages.hipblas
      rocmPackages.hipsparse
      rocmPackages.rocfft
      rocmPackages.rocrand
      rocmPackages.rocthrust

      # OpenCL
      ocl-icd
      opencl-headers
      clinfo

      # NVIDIA libraries
      libGL
      libGLU
      libglvnd
      vulkan-loader
      nvidia-vaapi-driver

      # System libraries
      zlib
      libpng
      libjpeg
      freetype
      fontconfig
      libx11
      libxext
      libxrender
      libxcb
      libxau
      libxdmcp
      SDL2
      alsa-lib
      systemd
      libusb1
      curl
      openssl
    ];

    # Git configuration now provided by common-host-defaults.nix
    # with automatic hostname interpolation (j_kro@forge)
  };

  # ============================================================================
  # TAILSCALE - Now managed by modules/system/tailscale.nix
  # ============================================================================
  # Tailscale routing automatically configured via network-constants
}

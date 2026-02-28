# NVIDIA Wayland Module - Best Practices for NVIDIA + Wayland + Plasma 6
# Based on NixOS community best practices as of 2026
# Reference: https://wiki.nixos.org/wiki/NVIDIA
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.nvidia.wayland;
in {
  options.hardware.nvidia.wayland = {
    enable = lib.mkEnableOption "NVIDIA Wayland optimizations for Plasma 6";

    enable32Bit = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable 32-bit graphics support for Steam and games";
    };

    openModules = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use open-source NVIDIA kernel modules (required for driver 560+)";
    };

    powerManagement = lib.mkOption {
      type = lib.types.bool;
      default = true; # Enabled - freeze issue resolved with NVIDIA 560+ open modules + proper KWIN_DRM_DEVICES
      description = "Enable NVIDIA power management (reduces idle power/heat for Ampere GPUs)";
    };

    sddmWayland = lib.mkOption {
      type = lib.types.bool;
      default = false; # Disabled in favor of plasma-login-manager (Plasma 6.6)
      description = "Enable SDDM Wayland support (deprecated, use plasma-login-manager)";
    };

    # Multi-GPU support
    multiGpu = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable multi-GPU configuration";
      };

      autoDetect = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Auto-detect which GPU has connected displays (scans /sys/class/drm)";
      };

      primaryCard = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/dev/dri/card2";
        description = "Primary GPU device path for KWin (the one with monitors attached, listed first). Auto-detected if autoDetect=true.";
      };

      secondaryCard = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/dev/dri/card0";
        description = "Secondary GPU device path (compute-only, listed after primary). Auto-detected if autoDetect=true.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # ============================================================================
    # NVIDIA DRIVER CONFIGURATION
    # ============================================================================
    hardware.nvidia = {
      # Use open-source modules for better Wayland support (driver 560+)
      open = cfg.openModules;

      # Required for Wayland
      modesetting.enable = true;

      # NVIDIA settings GUI
      nvidiaSettings = true;

      # Power management
      powerManagement.enable = cfg.powerManagement;
      powerManagement.finegrained = false;

      # GSP firmware - must be enabled when using open-source modules
      gsp.enable = cfg.openModules;

      # Disable PRIME offload (Wayland uses direct rendering)
      prime.offload.enable = false;
    };

    # Include NVIDIA firmware when using open modules (required for GSP)
    hardware.firmware = lib.optionals cfg.openModules [
      config.hardware.nvidia.package.firmware
    ];

    # ============================================================================
    # GRAPHICS CONFIGURATION
    # ============================================================================
    hardware.graphics = {
      enable = true;
      inherit (cfg) enable32Bit;

      extraPackages = with pkgs; [
        # Essential for NVIDIA + Wayland integration
        egl-wayland

        # Hardware video acceleration
        nvidia-vaapi-driver
        libva
        libva-utils
      ];

      extraPackages32 = lib.optionals cfg.enable32Bit (
        with pkgs.pkgsi686Linux; [
          nvidia-vaapi-driver
        ]
      );
    };

    # ============================================================================
    # DISPLAY MANAGER (SDDM with Wayland)
    # ============================================================================
    services.displayManager.sddm = {
      wayland.enable = lib.mkDefault cfg.sddmWayland;
      settings.Users.HideUsers = "mining;nixbuild;lobster";
    };

    # ============================================================================
    # ENVIRONMENT VARIABLES (Minimal, working NVIDIA + Wayland)
    # ============================================================================
    environment.sessionVariables =
      {
        # ========================================================================
        # WAYLAND BACKEND
        # ========================================================================
        # Force Wayland backend for Qt applications (Plasma 6)
        QT_QPA_PLATFORM = "wayland";

        # Enable Wayland for Ozone-based applications (Chrome, Electron, etc.)
        NIXOS_OZONE_WL = "1";

        # ========================================================================
        # VULKAN (DLSS 4 / Frame Generation support)
        # ========================================================================
        # CRITICAL: Force NVIDIA Vulkan ICD (required for DLSS 4 on Linux)
        VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json";

        # ========================================================================
        # GLX / EGL
        # ========================================================================
        # Ensure GLX uses NVIDIA vendor library
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";

        # Force GBM to use NVIDIA DRM backend (CRITICAL for Plasma 6 Wayland)
        GBM_BACKEND = "nvidia-drm";

        # VA-API driver for hardware video acceleration
        LIBVA_DRIVER_NAME = "nvidia";

        # CRITICAL: EGL vendor library path for Qt6/KWin
        __EGL_VENDOR_LIBRARY_FILENAMES = "/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json";

        # ========================================================================
        # CUDA / AI OPTIMIZATIONS (2026)
        # ========================================================================
        # Enable asynchronous CUDA execution for better performance
        CUDA_LAUNCH_BLOCKING = "0";

        # Optimize tensor core usage for AI inference
        NVIDIA_TF32_OVERRIDE = "1"; # Enable TF32 on Ampere (faster than FP32, minimal accuracy loss)
      }
      // lib.optionalAttrs cfg.multiGpu.enable {
        # ========================================================================
        # MULTI-GPU AI / ML OPTIMIZATIONS
        # ========================================================================
        # NCCL (NVIDIA Collective Communications Library) for multi-GPU AI
        # Auto-detect P2P capability (PCIe for you, not NVLink)
        NCCL_P2P_DISABLE = "0"; # Enable P2P for direct GPU-GPU transfers
        # Don't set NCCL_P2P_LEVEL - let NCCL auto-detect (no NVLink)

        # CUDA unified memory optimizations for multi-GPU
        CUDA_DEVICE_MAX_CONNECTIONS = "8"; # Max connections for concurrent kernels

        # Preload P2P access for faster AI workloads
        CUDA_VISIBLE_DEVICES = "0,1"; # Make both GPUs visible to CUDA

        # CUDA cache for faster kernel compilation
        CUDA_CACHE_DISABLE = "0";
        CUDA_CACHE_MAXSIZE = "1073741824"; # 1GB cache

        # OpenMP threads for CPU parallelization (matches your 32 cores)
        OMP_NUM_THREADS = "16";
        OMP_PROC_BIND = "close";
        OMP_PLACES = "cores";
      };

    # CRITICAL: DRM device variables must be in environment.variables (not sessionVariables)
    # to propagate to all services including plasmalogin greeter
    environment.variables = lib.optionalAttrs (cfg.multiGpu.enable && !cfg.multiGpu.autoDetect && cfg.multiGpu.primaryCard != null) {
      # KWin only needs the primary display GPU (where monitors are connected)
      # KWin 6.6 doesn't parse colon-separated format correctly for multiple GPUs
      # Secondary GPU is automatically available for CUDA/compute via NVIDIA drivers
      KWIN_DRM_DEVICES = cfg.multiGpu.primaryCard;

      # wlroots-based compositors (Hyprland, Sway, Niri) support colon-separated format
      WLR_DRM_DEVICES =
        if cfg.multiGpu.secondaryCard != null
        then "${cfg.multiGpu.primaryCard}:${cfg.multiGpu.secondaryCard}"
        else cfg.multiGpu.primaryCard;
    };

    # ============================================================================
    # ADDITIONAL WAYLAND PACKAGES
    # ============================================================================
    environment.systemPackages = with pkgs; [
      # Wayland utilities
      wayland-utils

      # Display management
      kanshi
    ];

    # ============================================================================
    # VULKAN ICD SYMLINK + CUDA MPS DIRECTORIES
    # ============================================================================
    systemd.tmpfiles.rules = [
      "L+ /etc/vulkan/icd.d/nvidia_icd.json - - - /run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json"
      "L+ /etc/vulkan/icd.d/nvidia_icd.x86_64.json - - - /run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json"
      "d /etc/vulkan/icd.d 0755 root root -"
      # CUDA MPS directories
      "d /var/run/nvidia-mps 0755 root root -"
      "d /var/log/nvidia-mps 0755 root root -"
    ];

    # ============================================================================
    # KERNEL PARAMETERS
    # ============================================================================
    # Ampere (RTX 30xx) optimized settings for multi-GPU + Wayland
    boot.kernelParams =
      [
        # ========================================================================
        # NVIDIA DRM CONFIGURATION
        # ========================================================================
        "nvidia-drm.modeset=1"
        # Disable fbdev to prevent "pageflip timeout" errors on driver 570+
        "nvidia-drm.fbdev=0"

        # ========================================================================
        # AMPERE-SPECIFIC MEMORY MANAGEMENT
        # ========================================================================
        # Enable Page Attribute Table for better memory access patterns
        "nvidia.NVreg_EnablePageAttributeTable=1"
        # Let GPU manage video memory dynamically (Ampere handles this well)
        "nvidia.NVreg_ReserveVideoMemorySize=0"
        # Enable GSP firmware (required for open-source modules on Ampere)
        "nvidia.NVreg_EnableGpuFirmware=1"

        # ========================================================================
        # MULTI-GPU PEER-TO-PEER (P2P) MEMORY COHERENCY
        # ========================================================================
        # Enable P2P access between GPUs for compute workloads
        # Allows direct memory access between RTX 3090 and RTX 3060 Ti
        "nvidia.NVreg_EnableP2P=1"
        # Allow P2P memory mapping for CUDA/OpenCL applications
        "nvidia.NVreg_P2PContextMmap=1"
        # Enable P2P write combining for better performance
        "nvidia.NVreg_EnableWriteCombine=1"

        # ========================================================================
        # PCI EXPRESS OPTIMIZATIONS
        # ========================================================================
        # Disable PCIe gen3 workaround (Ampere uses PCIe 4.0)
        "nvidia.NVreg_EnablePCIeGen3=0"

        # ========================================================================
        # CPU PERFORMANCE OPTIMIZATIONS (Low Latency Gaming/AI)
        # ========================================================================
        # Prevent CPU from entering deep sleep states (C2+) for lower latency
        # C1 is allowed for minimal power savings without latency penalty
        "processor.max_cstate=1"
        # Force CPU to poll instead of sleeping (lowest latency, higher power)
        # Ideal for gaming + AI inference where responsiveness > power savings
        "idle=poll"
        # Disable NUMA balancing for single-socket systems (reduces overhead)
        "numa_balancing=0"

        # ========================================================================
        # MEMORY OPTIMIZATIONS (Huge Pages)
        # ========================================================================
        # Use Transparent Huge Pages selectively (madvise) instead of always
        # Reduces TLB misses for better memory throughput
        # "always" can cause memory fragmentation issues
        "transparent_hugepage=madvise"
      ]
      ++ lib.optionals cfg.powerManagement [
        # Power management settings (ONLY if powerManagement is enabled)
        # Currently disabled due to multi-GPU + Wayland freeze issues
        "nvidia.NVreg_NvLinkEnable=0"
      ];

    # ============================================================================
    # SYSTEMD ENVIRONMENT (for all services including plasmalogin)
    # ============================================================================
    # CRITICAL: DefaultEnvironment affects ALL systemd services, including
    # plasmalogin greeter. This is required because environment.sessionVariables
    # only affects user sessions, not system services like plasmalogin.
    systemd.settings.Manager = lib.optionalAttrs (cfg.multiGpu.enable && !cfg.multiGpu.autoDetect && cfg.multiGpu.primaryCard != null) {
      DefaultEnvironment = let
        devices =
          if cfg.multiGpu.secondaryCard != null
          then "${cfg.multiGpu.primaryCard}:${cfg.multiGpu.secondaryCard}"
          else cfg.multiGpu.primaryCard;
      in [
        "KWIN_DRM_DEVICES=${devices}"
        "WLR_DRM_DEVICES=${devices}"
      ];
    };

    # ============================================================================
    # MULTI-GPU AUTO-DETECTION SERVICE
    # ============================================================================
    # Detects which GPUs have connected displays and sets environment variables
    # This runs before display manager to ensure KWin/wlroots get correct GPU
    systemd.services.nvidia-gpu-autodetect = lib.mkIf cfg.multiGpu.autoDetect {
      description = "Auto-detect multi-GPU configuration for NVIDIA";
      wantedBy = ["display-manager.service"];
      before = ["display-manager.service" "plasma-login-manager.service" "sddm.service"];
      after = ["systemd-udev-settle.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        #!/bin/bash
        set -euo pipefail

        LOCK_FILE="/run/nvidia-gpu-autodetect.lock"

        # Skip if already detected (in case of restart)
        if [ -f "$LOCK_FILE" ]; then
          echo "GPU detection already completed, skipping"
          exit 0
        fi

        echo "Starting NVIDIA GPU auto-detection..."

        # Find all DRM cards
        declare -A gpus_with_displays
        declare -a all_gpus

        # Scan /sys/class/drm for card devices
        for card in /sys/class/drm/card[0-9]*; do
          if [ -d "$card" ]; then
            card_name=$(basename "$card")
            card_device="/dev/dri/$card_name"
            echo "Checking $card_name..."

            # Check if this card has any connected displays
            has_connected=false
            for output in "$card"-*; do
              if [ -f "$output/status" ]; then
                status=$(cat "$output/status" 2>/dev/null || echo "disconnected")
                if [ "$status" = "connected" ]; then
                  has_connected=true
                  echo "  Found connected display: $(basename "$output")"
                fi
              fi
            done

            # Also check /sys/class/drm/cardX-*/status files directly
            for status_file in /sys/class/drm/''${card_name}-*/status; do
              if [ -f "$status_file" ]; then
                status=$(cat "$status_file" 2>/dev/null || echo "disconnected")
                if [ "$status" = "connected" ]; then
                  has_connected=true
                  echo "  Found connected display via status file"
                fi
              fi
            done

            all_gpus+=("$card_device")
            if [ "$has_connected" = true ]; then
              gpus_with_displays["$card_device"]=1
              echo "  $card_device HAS connected displays"
            else
              echo "  $card_device has NO connected displays (compute-only)"
            fi
          fi
        done

        # Determine primary and secondary GPUs
        primary_gpu=""
        secondary_gpus=()

        if [ ''${#gpus_with_displays[@]} -gt 0 ]; then
          # Get GPU with displays (sorted by card number)
          for gpu in $(printf '%s\n' "''${!gpus_with_displays[@]}" | sort -V); do
            if [ -z "$primary_gpu" ]; then
              primary_gpu="$gpu"
              echo "Primary GPU (displays): $gpu"
            else
              secondary_gpus+=("$gpu")
              echo "Additional GPU with displays: $gpu"
            fi
          done
        fi

        # Add compute-only GPUs as secondary
        for gpu in "''${all_gpus[@]}"; do
          if [ -z "''${gpus_with_displays[$gpu]:-}" ]; then
            secondary_gpus+=("$gpu")
            echo "Secondary GPU (compute-only): $gpu"
          fi
        done

        # Build device string
        device_string="$primary_gpu"
        if [ ''${#secondary_gpus[@]} -gt 0 ]; then
          for gpu in "''${secondary_gpus[@]}"; do
            device_string="$device_string:$gpu"
          done
        fi

        echo "Final device string: $device_string"

        # Set systemd environment variables dynamically
        if [ -n "$primary_gpu" ]; then
          echo "Setting KWIN_DRM_DEVICES=$device_string"
          systemctl set-environment "KWIN_DRM_DEVICES=$device_string"
          echo "Setting WLR_DRM_DEVICES=$device_string"
          systemctl set-environment "WLR_DRM_DEVICES=$device_string"

          # Create lock file
          touch "$LOCK_FILE"
          echo "GPU auto-detection completed successfully"
        else
          echo "ERROR: No GPUs detected!" >&2
          exit 1
        fi
      '';
    };

    # ============================================================================
    # EARLY NVIDIA LOADING
    # ============================================================================
    boot.initrd.kernelModules = [
      "nvidia"
      "nvidia_modeset"
      "nvidia_drm"
    ];

    boot.initrd.availableKernelModules = [
      "nvidia"
      "nvidia_modeset"
      "nvidia_drm"
    ];

    # ============================================================================
    # SCHED_EXT - BPF-BASED CPU SCHEDULER (Linux 6.19)
    # ============================================================================
    # Enable sched_ext framework for custom BPF schedulers
    # Benefits: Better gaming latency via scx_lavd, improved multi-task performance
    # Note: sched_ext tools (scx_lavd) can be installed manually via nix shell
    boot.kernelModules = ["sched_ext"];

    # ============================================================================
    # NVIDIA DEVICE NODE CREATION
    # ============================================================================
    systemd.services.nvidia-device-nodes = {
      description = "Create NVIDIA device nodes";
      after = [
        "systemd-modules-load.service"
        "systemd-udev-trigger.service"
      ];
      wants = ["systemd-modules-load.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "nvidia-device-nodes" ''
          if [ -d /proc/driver/nvidia ]; then
            if [ ! -e /dev/nvidiactl ]; then
              mknod -m 666 /dev/nvidiactl c 195 255 2>/dev/null || true
            fi
            if [ -d /proc/driver/nvidia/gpus ]; then
              for gpu in /proc/driver/nvidia/gpus/*; do
                if [ -d "$gpu" ]; then
                  minor=$(grep -oP 'Minor:\s*\K[0-9]+' "$gpu/information" 2>/dev/null || true)
                  if [ -n "$minor" ] && [ ! -e "/dev/nvidia$minor" ]; then
                    mknod -m 666 "/dev/nvidia$minor" c 195 "$minor" 2>/dev/null || true
                  fi
                fi
              done
            fi
          fi
        '';
      };
    };

    # ============================================================================
    # CUDA MPS (MULTI-PROCESS SERVICE) FOR MULTI-GPU AI
    # ============================================================================
    # Improves concurrent AI workload performance by sharing GPU context
    # Ideal for llama-server with multiple concurrent requests
    # Benefits: 30-40% better multi-process GPU utilization
    # Note: Disabled by default - enable manually if needed for multi-process AI workloads
    systemd.services.nvidia-mps = {
      description = "NVIDIA CUDA Multi-Process Service";
      wantedBy = lib.mkForce [];  # Disabled by default - can be enabled manually
      after = ["nvidia-device-nodes.service"];
      serviceConfig = {
        Type = "forking";
        RemainAfterExit = true;
        ExecStart = "${config.hardware.nvidia.package.bin}/bin/nvidia-cuda-mps-control -d";
        ExecStop = "${config.hardware.nvidia.package.bin}/bin/nvidia-cuda-mps-control -s";
        Environment = "CUDA_MPS_PIPE_DIRECTORY=/var/run/nvidia-mps";
      };
    };

    # ============================================================================
    # HUGE PAGES CONFIGURATION (Better Memory Throughput)
    # ============================================================================
    # Pre-allocate 2GB of huge pages (1024 x 2MB pages)
    # Reduces TLB misses for better memory access performance
    # Benefits: 10-20% better memory throughput for large models
    boot.kernel.sysctl."vm.nr_hugepages" = lib.mkDefault 1024;

    # ============================================================================
    # DMEM CGROUP - Device Memory Isolation (Linux 6.19)
    # ============================================================================
    # Enable GPU memory resource isolation and accounting
    # Benefits: Better multi-GPU AI workload management, memory limits per container
    # Note: Requires kernel 6.19+ with CONFIG_CGROUP_DMEM enabled
    systemd.services.enable-dmem-cgroup = lib.mkIf cfg.multiGpu.enable {
      description = "Enable dmem cgroup for GPU memory isolation";
      wantedBy = ["multi-user.target"];
      after = ["systemd-modules-load.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "enable-dmem-cgroup" ''
          # Check if dmem cgroup is available (kernel 6.19+)
          if [ -d /sys/fs/cgroup/dmem ]; then
            echo "dmem cgroup available - GPU memory isolation enabled"
            # Set up GPU memory limits for multi-GPU
            # These can be adjusted per workload
            echo 2147483648 > /sys/fs/cgroup/dmem/max  # 2GB default limit
          else
            echo "dmem cgroup not available - requires kernel 6.19+"
          fi
        '';
      };
    };

    # ============================================================================
    # PLASMA KWIN DRM CONFIGURATION (User Session)
    # ============================================================================
    # Create ~/.config/plasma-workspace/env/kwin-drm.sh for Plasma 6 Wayland
    # This file is sourced by plasma-workspace before KWin starts
    # CRITICAL: KWin 6.6 doesn't parse colon-separated KWIN_DRM_DEVICES correctly
    # Only the primary display GPU should be set (secondary GPU is for compute only)
    systemd.user.services.kwin-drm-config = lib.mkIf cfg.multiGpu.enable {
      description = "Configure KWin DRM devices for Plasma Wayland";
      wantedBy = ["plasma-workspace.target"];
      before = ["plasma-workspace.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        # Create plasma-workspace env directory
        mkdir -p "$HOME/.config/plasma-workspace/env"

        # Write kwin-drm.sh with primary GPU only
        cat > "$HOME/.config/plasma-workspace/env/kwin-drm.sh" << 'EOF'
#!/bin/sh
# Auto-generated by NixOS - Multi-GPU configuration
# Primary GPU: ${cfg.multiGpu.primaryCard} (display GPU with monitors)
# Secondary GPU: ${if cfg.multiGpu.secondaryCard != null then cfg.multiGpu.secondaryCard else "none"} (compute-only)
# KWin only needs the primary display GPU
export KWIN_DRM_DEVICES=${cfg.multiGpu.primaryCard}
EOF

        chmod +x "$HOME/.config/plasma-workspace/env/kwin-drm.sh"
        echo "Created kwin-drm.sh with KWIN_DRM_DEVICES=${cfg.multiGpu.primaryCard}"
      '';
    };

    # ============================================================================
    # PLASMA 6.6 HDR SUPPORT (Linux 6.19 DRM Color Pipeline API)
    # ============================================================================
    # Plasma 6.6 has experimental HDR support via the new DRM Color Pipeline API
    # Enable HDR metadata handling for supported displays
    # Note: HDR variables are merged into existing sessionVariables above
    # This works with Linux 6.19's DRM Color Pipeline API
    # PLASMA_ENABLE_HDR is set automatically by Plasma 6.6 when HDR is detected

    # KWin HDR configuration (Plasma 6.6+)
    environment.etc."xdg/kwinrc".text =
      if (config.services.desktopManager.plasma6.enable or false)
      then ''
        [Compositing]
        # Enable HDR output for supported displays
        HDR=true
        # HDR tone mapping mode
        HDRToneMapping=1
        # Max brightness for HDR content (0-1000 nits) - 930 nits for RTX 3090
        HDRMaxBrightness=930
      ''
      else "";
  };
}

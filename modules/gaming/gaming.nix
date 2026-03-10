# Gaming Module - Steam, GameMode, Gamescope, MangoHud
# VR (WiVRn) is gated by services.gaming.vr.enable option
{
  config,
  lib,
  pkgs,
  inputs ? null,
  ...
}:
with lib; let
  cfg = config.services.gaming;
  vrCfg = cfg.vr;
in {
  options.services.gaming = {
    enable = mkEnableOption "Gaming support (Steam, GameMode, Gamescope)";

    vr = {
      enable = mkEnableOption "VR support (WiVRn, SteamVR, OpenXR)";
      encoder = mkOption {
        type = types.enum ["nvenc" "x264" "av1"];
        default = "nvenc";
        description = "Video encoder for WiVRn streaming";
      };
      refreshRate = mkOption {
        type = types.int;
        default = 90;
        description = "Target refresh rate for VR headset";
      };
      resolution = mkOption {
        type = types.str;
        default = "2160x2160";
        description = "Per-eye resolution for VR streaming";
      };
    };
  };

  config = mkMerge [
    # Base gaming configuration (always when gaming.enable = true)
    (mkIf cfg.enable {
      # ============================================================================
      # PROGRAMS - GameMode, Steam, Gamescope, nix-ld
      # ============================================================================
      programs = {
        # GameMode - CPU/GPU Optimizations
        gamemode = {
          enable = true;
          settings = {
            general = {
              desiredgov = "performance";
              use_systemd = true;
              softrealtime = "auto";
              renice = 15;
              ioprio = 0;
            };
            gpu = {
              apply_gpu_optimisations = "accept-responsibility";
              nv_powermizer_mode = 1;
              # Moderate overclock values - balanced stability/performance
              # Conservative: 50MHz core, 200MHz memory (safer starting point)
              # Current: 100MHz core, 400MHz memory (balanced)
              # Aggressive: 150MHz core, 500MHz memory (may cause instability)
              nv_core_clock_mhz_offset = 100;
              nv_mem_clock_mhz_offset = 400;
            };
            custom = {
              start = "${pkgs.libnotify}/bin/notify-send 'GameMode activated' 'Performance optimizations enabled'";
              end = "${pkgs.libnotify}/bin/notify-send 'GameMode deactivated' 'Normal performance restored'";
            };
          };
        };

        # Steam - Game launcher and Proton manager
        steam = {
          enable = true;
          fontPackages = with pkgs; [
            noto-fonts
            liberation_ttf
            dejavu_fonts
          ];
          extraCompatPackages = with pkgs;
            optionals (inputs != null && inputs ? nixpkgs-xr) [
              inputs.nixpkgs-xr.packages."x86_64-linux".proton-ge-rtsp-bin
            ];
          remotePlay.openFirewall = true;
          dedicatedServer.openFirewall = true;
          localNetworkGameTransfers.openFirewall = true;
          package = pkgs.steam.override {
            extraLibraries = pkgs:
              with pkgs; [
                freetype
                fontconfig
                libpng
                libjpeg
                libtiff
                vulkan-loader
                vulkan-tools
                libxcursor
                libxi
                libxinerama
                libxscrnsaver
                libpulseaudio
                libvorbis
                stdenv.cc.cc.lib
                libkrb5
                keyutils
                libcap
                SDL2
              ];
            extraProfile = ''
              # LVRA recommendation for VRChat timezone display
              unset TZ

              cd $HOME

              # OpenXR/VR support - critical for WiVRn
              export PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1
              export PRESSURE_VESSEL_FILESYSTEMS_RW=$XDG_RUNTIME_DIR/wivrn/comp_ipc

              # Steam container paths
              export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam"
              export STEAM_COMPAT_DATA_PATH="$HOME/.local/share/Steam/steamapps/compatdata"
              export STEAM_EXTRA_COMPAT_TOOLS_PATHS="$HOME/.local/share/Steam/compatibilitytools.d"

              # OpenVR -> OpenXR translation via xrizer
              export OPENVR_API_PATH="${pkgs.xrizer}/lib/xrizer"
            '';
          };
        };

        # Gamescope - Frame generation/upscaling
        gamescope = {
          enable = true;
          capSysNice = true;
          env = {
            __GL_SHADER_DISK_CACHE_SKIP_CLEANUP = "1";
            __GL_SHADER_DISK_CACHE_SIZE = "1073741824";
            __GL_SHADER_DISK_CACHE_PATH = "/var/cache/nvidia-shader-cache";
            __GLX_FORCE_MONO = "0";
            __GL_ALLOW_FXAA_USAGE = "1";
            # HDR configuration - ENABLE_GAMESCOPE_WSI=1 is the standard value
            ENABLE_GAMESCOPE_WSI = "1";
            DXVK_HDR = "1";
          };
          args = [
            "--immediate-flips"
            "--rt"
            "--steam"
            "--xwayland-count 2"
            "--force-composition"
            "--expose-wayland"
          ];
        };

        # nix-ld for running non-NixOS binaries
        nix-ld = {
          enable = true;
          libraries = with pkgs; [
            freetype
            fontconfig
            libpng
            libjpeg
            libtiff
            libpulseaudio
            libvorbis
            libkrb5
            keyutils
            libxcursor
            libxi
            libxinerama
            libxscrnsaver
            vulkan-loader
            vulkan-tools
            stdenv.cc.cc.lib
            pkgsi686Linux.stdenv.cc.cc.lib
            pkgsi686Linux.zlib
            libgcrypt
            libgpg-error
            libusb1
            udev
            libusb-compat-0_1
          ];
        };
      };

      hardware.steam-hardware.enable = true;

      # ============================================================================
      # SYSTEMD - SCX scheduler
      # ============================================================================
      # scx_lavd provides better gaming performance than CFS for mixed workloads
      # It prioritizes latency-sensitive tasks (games) over background work
      systemd.services.scx-lavd = {
        description = "SCX lavd scheduler user-space daemon";
        wantedBy = ["multi-user.target"];
        after = ["network.target"];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.scx.full}/bin/scx_lavd --autopilot";
          Restart = "on-failure";
          RestartSec = "5s";
          Nice = -20;
          IOSchedulingClass = "realtime";
          IOSchedulingPriority = 7;
        };
      };

      # ============================================================================
      # SERVICES - PipeWire, udev rules
      # ============================================================================
      services = {
        # PipeWire low-latency configuration
        pipewire.extraConfig = lib.mkForce {
          pipewire."99-lowlatency"."context.properties" = {
            "default.clock.min-quantum" = 64;
            "default.clock.max-quantum" = 2048;
          };
          pipewire-pulse."99-lowlatency"."pulse.min.quantum" = "64/48000";
          client."99-lowlatency"."stream.properties"."node.latency" = "64/48000";
        };

        # Disable DualSense/DualShock touchpad to prevent drift in games
        udev.extraRules = ''
          # Disable DualSense (PS5) touchpad
          # Match by device name from parent (ATTRS) and unique touchpad capabilities
          # The touchpad has unique ABS capabilities: 260800000000003
          SUBSYSTEM=="input", ATTRS{name}=="*DualSense*Touchpad*", ENV{LIBINPUT_IGNORE_DEVICE}="1"
          SUBSYSTEM=="input", ATTRS{name}=="*DualShock*Touchpad*", ENV{LIBINPUT_IGNORE_DEVICE}="1"
          # Fallback: Match by capability signature if name matching fails
          SUBSYSTEM=="input", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", ATTRS{capabilities/abs}=="260800000000003", ENV{LIBINPUT_IGNORE_DEVICE}="1"

          # DualSense (PS5) hidraw access for Wine/Proton controller support
          KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", MODE="0660", TAG+="uaccess"
          # DualSense (PS5) over Bluetooth
          KERNEL=="hidraw*", KERNELS=="*054C:0CE6*", MODE="0660", TAG+="uaccess"
          # DualShock 4 (PS4) hidraw access
          KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="05c4", MODE="0660", TAG+="uaccess"
          KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="09cc", MODE="0660", TAG+="uaccess"
        '';
      };

      # Create plugdev group for backwards compatibility
      # Note: TAG+="uaccess" (above) provides the same functionality via systemd-logind
      users.groups.plugdev = {};

      systemd.tmpfiles.rules = [
        "d /var/cache/nvidia-shader-cache 0755 root root - -"
        # ldconfig is in glibc.bin output, not glibc.out
        "L /sbin/ldconfig - - - - ${lib.getBin pkgs.glibc}/sbin/ldconfig"
        # Joystick calibration directory
        "d /etc/joystick 0755 root root - -"
      ];

      # ============================================================================
      # ENVIRONMENT - Session variables, packages, DualSense config
      # ============================================================================
      environment = {
        # Common session variables (gaming + MangoHud defaults)
        sessionVariables = {
          PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES = "1";
          WINE_FULLSCREEN_FAKE_CAPTURE = "1";
          # Note: SDL_VIDEODRIVER is NOT set - let Steam/Proton auto-detect the best backend
          # This fixes VRChat and other games that benefit from native Wayland support
          # MangoHud default configuration (can be overridden per-game)
          MANGOHUD_CONFIG = "fps,frametime,cpu_stats,gpu_stats,vram,ram,cpu_temp,gpu_temp,core_load,background_alpha=0.5,position=top-left,toggle_hud=Shift_R+F12";
          # Auto-reload GameMode config when launching games
          GAMEMODE_AUTO_RELOAD_CONFIG = "1";
          # SDL2 GameControllerDB path for custom controller mappings and deadzones
          SDL_GAMECONTROLLERDB = "/etc/sdl2-dualsense-db";
        };

        # Common gaming packages
        systemPackages = with pkgs; [
          gamescope
          mangohud
          goverlay
          gamemode
          scx.full
          (pkgs.writeShellScriptBin "launch-game" ''
            #!/usr/bin/env bash
            # launch-game - Wrapper to run games in gaming.slice with GameMode
            # Usage: launch-game [command] [args...]
            #
            # Examples:
            #   launch-game steam
            #   launch-game lutris
            #   launch-game heroic
            #   launch-game /path/to/game executable
            #
            # Per-game configuration via GameMode:
            # Create ~/.config/gamemode.ini with per-game settings:
            #   [game/executable-name]
            #   governor=performance
            #   gpu_optimisations=1

            set -euo pipefail

            # Validate arguments
            if [ $# -eq 0 ]; then
              echo "Usage: launch-game [command] [args...]" >&2
              echo "Launch a game in gaming.slice with GameMode integration" >&2
              echo "" >&2
              echo "Examples:" >&2
              echo "  launch-game steam" >&2
              echo "  launch-game lutris game://12345" >&2
              echo "  launch-game heroic" >&2
              echo "  launch-game /opt/game/bin/game.exe" >&2
              echo "" >&2
              echo "Per-game config: ~/.config/gamemode.ini" >&2
              exit 1
            fi

            # Check if gaming.slice exists
            if ! systemctl show gaming.slice >/dev/null 2>&1; then
              echo "Warning: gaming.slice not found, running without cgroup isolation" >&2
              exec "$@"
            fi

            # Launch the game in gaming.slice with GameMode
            exec systemd-run --user \
              --slice=gaming.slice \
              --property=CPUWeight=1024 \
              --property=IOWeight=1000 \
              --property=Nice=-5 \
              --property=IOSchedulingClass=best-effort \
              --property=IOSchedulingPriority=4 \
              --collect \
              --quiet \
              -- "$@"
          '')
        ];

        etc = {
          # DualSense deadzone configuration
          # System-wide minimal deadzone for DualSense controller right stick
          # Applied via evdev at kernel level - affects all games
          "joystick/DualSense Wireless Controller".source = pkgs.writeText "dualsense-deadzone" ''
            # Sony DualSense Wireless Controller
            # Left stick: 2% deadzone (movement, maintains sensitivity)
            # Right stick: 2% horizontal, 5% vertical (camera - vertical only has drift)

            # evdev calibration format
            evdev ABS_X 2   # Left stick X
            evdev ABS_Y 2   # Left stick Y
            evdev ABS_RX 2  # Right stick X (horizontal camera) - 2%
            evdev ABS_RY 5  # Right stick Y (vertical camera) - 5%
          '';

          # SDL2 GameControllerDB with deadzone hints
          # Note: SDL2 deadzone is global - right stick gets 5% in evdev layer
          "SDL_gamecontrollerdb".source = pkgs.writeText "sdl2-dualsense-db" ''
            # SDL2 GameControllerDB entry for DualSense with deadzone hints
            # Format: SDL_GAMECONTROLLERDB_V2
            # Deadzone hint format: Deadzone:percentage  (e.g., Deadzone:2 = 2%)

            0300000054c0ce60000000000000000,DualSense Wireless Controller,a:b0:b1:b2:b3:b4:b5:b6:b7:b8:b9:b10:b11:b12:b13:b14:b15:b16:b17:b18:b19:b20:b21:b22:b23:b24,b:255,b:255,b:255,platform:Linux,
            0300000054c0ce60000000000000000,DualSense Wireless Controller,a:b0:b1:b2:b3:b4:b5:b6:b7:b8:b9:b10:b11:b12:b13:b14:b15:b16:b17:b18:b19:b20:b21:b22:b23:b24,b:255,b:255,b:255,platform:Linux,Deadzone:5,
          '';
        };
      };

      # ============================================================================
      # MANGOHUD - Performance overlay
      # ============================================================================
      # Note: Configuration is handled via MANGOHUD_CONFIG env var (set in sessionVariables)
      # or ~/.config/MangoHud/MangoHud.conf (can be managed via GOverlay)
    })

    # VR configuration (only when vr.enable = true)
    (mkIf vrCfg.enable {
      # ============================================================================
      # SERVICES - Avahi for WiVRn discovery, WiVRn streaming
      # ============================================================================
      services = {
        # Avahi - Required for WiVRn server discovery
        avahi = {
          enable = true;
          nssmdns4 = true;
          openFirewall = true;
        };

        # WiVRn - Wireless VR Streaming for Quest Headsets
        wivrn = {
          enable = true;
          openFirewall = true;
          defaultRuntime = true;
          autoStart = true;
        };

        # VR device udev rules
        udev.extraRules = ''
          # Oculus Rift
          SUBSYSTEM=="usb", ATTR{idVendor}=="2833", ATTR{idProduct}=="0181", MODE="0666", TAG+="uaccess"

          # Valve Index / Vive
          SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2101", MODE="0666", TAG+="uaccess"
          SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2102", MODE="0666", TAG+="uaccess"
          SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2102", MODE="0666", TAG+="uaccess"

          # HTC Vive
          SUBSYSTEM=="usb", ATTR{idVendor}=="0bb4", ATTR{idProduct}=="2c87", MODE="0666", TAG+="uaccess"
        '';
      };

      # VR firewall ports
      networking.firewall = {
        allowedTCPPorts = [9757];
        allowedUDPPorts = [
          9757
          5353
          9947
          27036
          27031
        ];
      };

      # VR kernel modules
      boot.kernelModules = [
        "usbhid"
        "uvcvideo"
        "nvidia-uvm"
        "hid-sensor-hub"
        "uinput"
      ];

      # VR graphics packages
      hardware.graphics.extraPackages = with pkgs; [
        freetype
        fontconfig
        libpng
        libjpeg
        libtiff
      ];
      # NOTE: extraPackages32 removed - breaks Wayland on multi-NVIDIA

      # ============================================================================
      # ENVIRONMENT - VR session variables and packages
      # ============================================================================
      environment = {
        # VR-specific session variables
        sessionVariables = {
          OPENVR_API_PATH = "${pkgs.xrizer}/lib/xrizer";
        };

        # VR-specific packages
        systemPackages = with pkgs; ([
            wivrn
            openxr-loader
            opencomposite
            openvr
            xrizer
            motoc
            # VR font/graphics dependencies
            freetype
            fontconfig
            libpng
            libjpeg
            libtiff
            ffmpeg
          ]
          ++ optionals (inputs != null && inputs ? nixpkgs-xr) [
            inputs.nixpkgs-xr.packages.${pkgs.stdenv.hostPlatform.system}.oscavmgr
          ]
          ++ [
            # GPU profile command (merged here to avoid duplicate assignment)
            (pkgs.writeShellScriptBin "gpu-profile" ''
              exec ${./scripts/gpu-profiles/switch-profile} "$@"
            '')
          ]);
      };

      # ============================================================================
      # AUTONOMOUS GPU WORKLOAD MONITOR
      # ============================================================================
      # Automatically detects workload type (gaming/AI/mining/idle)
      # and switches GPU profiles accordingly
      # Pauses mining when gaming or AI workloads are detected

      systemd.services.compute-workload-monitor = {
        description = "Autonomous compute workload monitor and resource manager";
        after = ["nvidia-persistence-mode.service" "network.target"];
        wantedBy = ["multi-user.target"];
        path = with pkgs; [
          # System utilities
          procps # pgrep
          systemd # systemctl
        ];
        serviceConfig = {
          Type = "simple";
          Environment = "PATH=${lib.makeBinPath (with pkgs; [procps systemd])}:/run/current-system/sw/bin";
          ExecStart = "${pkgs.writeShellScriptBin "compute-workload-monitor" ''
            # Autonomous GPU Workload Monitor
            # Detects workload type and adjusts GPU profiles automatically
            # Manages mining pauses when AI/Gaming workloads detected

            set -euo pipefail

            LOG_FILE="/var/log/compute-workload-monitor.log"
            MINING_SERVICES=("lolminer-nvidia" "xmrig")
            AI_PROCESSES=("lmstudio" "ollama" "python.*llm" "ai-inference-gateway")
            GAMING_PROCESSES=("steam" "lutris" "heroic" "wine" "proton")
            BUILD_PROCESSES=("nixos-rebuild" "colmena" "nix-build" "gcc" "clang" "cargo build" "make" "cmake" "ninja")

            log() {
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
            }

            check_process_running() {
                local process="$1"
                pgrep -f "$process" >/dev/null
            }

            check_incoming_build_job() {
                # Detect distributed build jobs from coordinators via SSH
                # This catches when nix-daemon on worker receives build job from coordinator
                local coordinators=("zephyr" "nexus" "forge")
                local hostname=$(get_hostname)

                # Skip if we are the coordinator (we already detect nix-build directly)
                for coord in "''${coordinators[@]}"; do
                    if [ "$hostname" = "$coord" ]; then
                        continue
                    fi

                    # Check for SSH connections from known coordinators
                    if command -v ss >/dev/null 2>&1; then
                        if ss -tnp 2>/dev/null | grep -q "ESTAB .*''${coord}.*ssh"; then
                            # Check if nix-daemon is using significant CPU (>30%)
                            local nix_pid=$(pgrep -o nix-daemon | head -1)
                            if [ -n "$nix_pid" ]; then
                                local nix_cpu=$(ps -p "$nix_pid" -o %cpu 2>/dev/null | tail -1)
                                if [ -n "$nix_cpu" ] && [ "$nix_cpu" != "%CPU" ]; then
                                    # Use bc for floating point comparison (30.0 threshold)
                                    if [ "$nix_cpu" \> "30.0" ] 2>/dev/null; then
                                        log "Detected incoming build from ''${coord} (nix-daemon CPU: ''${nix_cpu}%)"
                                        return 0
                                    fi
                                fi
                            fi
                        fi
                    fi
                done

                return 1
            }

            get_workload_type() {
                # Priority: Gaming > AI > Builds > Mining > Idle

                # Check for gaming
                for proc in "''${GAMING_PROCESSES[@]}"; do
                    if check_process_running "$proc"; then
                        echo "gaming"
                        return
                    fi
                done

                # Check for AI workloads
                for proc in "''${AI_PROCESSES[@]}"; do
                    if check_process_running "$proc"; then
                        echo "ai"
                        return
                    fi
                done

                # Check for build processes
                for proc in "''${BUILD_PROCESSES[@]}"; do
                    if check_process_running "$proc"; then
                        echo "builds"
                        return
                    fi
                done

                # Check for incoming distributed build jobs (worker detection)
                if check_incoming_build_job; then
                    echo "builds"
                    return
                fi

                # Check for active mining
                for service in "''${MINING_SERVICES[@]}"; do
                    if systemctl is-active --quiet "$service"; then
                        # Mining is only active if no higher priority workload
                        echo "mining"
                        return
                    fi
                done

                echo "idle"
            }

            # Helper function to get available GPU list
            get_gpu_list() {
                nvidia-smi --query-gpu=index --format=csv,noheader,nounits 2>/dev/null || echo ""
            }

            # Helper function to get GPU name
            get_gpu_name() {
                local gpu_id="$1"
                nvidia-smi -i "$gpu_id" --query-gpu=name --format=csv,noheader 2>/dev/null || echo "Unknown"
            }

            # Helper to safely apply nvidia-smi command
            nvidia_safe() {
                "$@" 2>/dev/null || true
            }

            # Host-specific mining policies
            get_hostname() {
                hostname
            }

            get_xmrig_gaming_threads() {
                local host=$(get_hostname)
                case "$host" in
                    nexus)  echo "4" ;;   # 17% of 24 threads
                    sentry) echo "4" ;;   # 25% of 16 threads
                    *)      echo "4" ;;   # Conservative default
                esac
            }

            get_xmrig_idle_threads() {
                local host=$(get_hostname)
                case "$host" in
                    nexus)  echo "12" ;;  # 50% of 24 threads
                    sentry) echo "8" ;;   # 50% of 16 threads
                    *)      echo "8" ;;   # Conservative default
                esac
            }

            reduce_xmrig_threads() {
                local target_threads=$1
                log "Reducing XMRig threads to $target_threads"

                # Get current XMRig PID
                local xmrig_pid=$(pgrep -f "xmrig.*--threads" | head -1)
                if [ -z "$xmrig_pid" ]; then
                    log "No XMRig process found"
                    return 1
                fi

                # Reduce effective threads using CPU affinity
                # This limits which cores XMRig can use without restarting
                local cores_to_use=$target_threads
                taskset -cp "$xmrig_pid" "0-$((cores_to_use - 1))" 2>/dev/null
                log "Set XMRig (PID $xmrig_pid) CPU affinity to cores 0-$((cores_to_use - 1))"
            }

            reset_xmrig_threads() {
                local target_threads=$1
                log "Resetting XMRig threads to $target_threads"

                local xmrig_pid=$(pgrep -f "xmrig.*--threads" | head -1)
                if [ -z "$xmrig_pid" ]; then
                    log "No XMRig process found"
                    return 1
                fi

                # Reset to use all available cores
                taskset -cp "$xmrig_pid" 0-FFFFFFFF 2>/dev/null
                log "Reset XMRig (PID $xmrig_pid) CPU affinity to all cores"
            }

            pause_xmrig() {
                log "Pausing XMRig completely"
                systemctl stop xmrig
            }

            resume_xmrig() {
                local threads=$1
                log "Resuming XMRig with $threads threads"
                systemctl start xmrig
            }

            apply_gaming_profile() {
                echo "=== Applying GPU GAMING profile ==="

                local gpus=$(get_gpu_list)
                local gpu_count=$(echo "$gpus" | wc -l)

                if [ "$gpu_count" -eq 0 ]; then
                    echo "WARNING: No NVIDIA GPUs detected"
                    return 0
                fi

                echo "Detected $gpu_count GPU(s) for gaming profile"

                for gpu_id in $gpus; do
                    local gpu_name=$(get_gpu_name "$gpu_id")
                    echo "Configuring GPU $gpu_id ($gpu_name)..."

                    case "$gpu_name" in
                        *"3060"*)
                            # 3060 Ti: Max performance
                            nvidia_safe nvidia-smi -i "$gpu_id" -pl 200
                            nvidia_safe nvidia-smi -i "$gpu_id" -lgc 2100
                            nvidia_safe nvidia-smi -i "$gpu_id" -lmc 7000
                            echo "  3060 Ti: 2100 MHz GPU, 7000 MHz mem, 200W limit"
                            ;;
                        *"3090"*)
                            # 3090: Aggressive GPU (liquid cooled), conservative VRAM
                            nvidia_safe nvidia-smi -i "$gpu_id" -pl 350
                            nvidia_safe nvidia-smi -i "$gpu_id" -lgc 2050
                            nvidia_safe nvidia-smi -i "$gpu_id" -lmc 7500
                            echo "  3090: 2050 MHz GPU (liquid-cooled), 7500 MHz mem, 350W limit"
                            ;;
                        *)
                            # Default: Max performance
                            nvidia_safe nvidia-smi -i "$gpu_id" -pl 250
                            nvidia_safe nvidia-smi -i "$gpu_id" -rgc
                            nvidia_safe nvidia-smi -i "$gpu_id" -rmc
                            echo "  $gpu_name: Default max performance profile"
                            ;;
                    esac
                done

                echo "GAMING profile applied: Mode: Maximum performance"

                # Pause GPU mining completely (gaming needs 100% GPU)
                if systemctl is-active --quiet lolminer-nvidia; then
                    log "Limiting lolminer-nvidia to 0% CPU for gaming"
                    systemctl set-property lolminer-nvidia.service CPUQuota="0%" --runtime
                fi

                if systemctl is-active --quiet lolminer-amd; then
                    log "Limiting lolminer-amd to 0% CPU for gaming"
                    systemctl set-property lolminer-amd.service CPUQuota="0%" --runtime
                fi

                # Reduce CPU mining to 25% (free CPU for game logic)
                if systemctl is-active --quiet xmrig; then
                    log "Limiting xmrig to 25% CPU for gaming"
                    systemctl set-property xmrig.service CPUQuota="25%" --runtime
                fi
            }

            apply_ai_profile() {
                echo "=== Applying GPU AI INFERENCE profile ==="

                local gpus=$(get_gpu_list)
                local gpu_count=$(echo "$gpus" | wc -l)

                if [ "$gpu_count" -eq 0 ]; then
                    echo "WARNING: No NVIDIA GPUs detected"
                    return 0
                fi

                echo "Detected $gpu_count GPU(s) for AI inference profile"

                for gpu_id in $gpus; do
                    local gpu_name=$(get_gpu_name "$gpu_id")
                    echo "Configuring GPU $gpu_id ($gpu_name)..."

                    case "$gpu_name" in
                        *"3060"*)
                            # 3060 Ti: Balanced
                            nvidia_safe nvidia-smi -i "$gpu_id" -pl 110
                            nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1950
                            nvidia_safe nvidia-smi -i "$gpu_id" -lmc 6200
                            echo "  3060 Ti: 1950 MHz GPU, 6200 MHz mem, 110W limit"
                            ;;
                        *"3090"*)
                            # 3090: Liquid cooled, can push harder
                            nvidia_safe nvidia-smi -i "$gpu_id" -pl 300
                            nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1900
                            nvidia_safe nvidia-smi -i "$gpu_id" -lmc 7000
                            echo "  3090: 1900 MHz GPU (liquid-cooled), 7000 MHz mem, 300W limit"
                            ;;
                        *)
                            # Default: Balanced
                            nvidia_safe nvidia-smi -i "$gpu_id" -pl 200
                            nvidia_safe nvidia-smi -i "$gpu_id" -rgc
                            nvidia_safe nvidia-smi -i "$gpu_id" -rmc
                            echo "  $gpu_name: Default balanced profile"
                            ;;
                    esac
                done

                echo "AI INFERENCE profile applied: Mode: Balanced performance with thermal safety"

                # Pause GPU mining completely (AI needs 100% GPU)
                if systemctl is-active --quiet lolminer-nvidia; then
                    log "Limiting lolminer-nvidia to 0% CPU for AI inference"
                    systemctl set-property lolminer-nvidia.service CPUQuota="0%" --runtime
                fi

                if systemctl is-active --quiet lolminer-amd; then
                    log "Limiting lolminer-amd to 0% CPU for AI inference"
                    systemctl set-property lolminer-amd.service CPUQuota="0%" --runtime
                fi

                # Keep CPU mining at 100% (GPU is bottleneck, CPU just coordinates)
                if systemctl is-active --quiet xmrig; then
                    log "Keeping xmrig at 100% CPU (GPU is bottleneck for AI)"
                    systemctl set-property xmrig.service CPUQuota="100%" --runtime
                fi
            }

            apply_builds_profile() {
                echo "=== Applying GPU/CPU BUILDS profile ==="

                local gpus=$(get_gpu_list)
                local gpu_count=$(echo "$gpus" | wc -l)

                if [ "$gpu_count" -eq 0 ]; then
                    echo "WARNING: No NVIDIA GPUs detected"
                else
                    echo "Detected $gpu_count GPU(s) for builds profile"
                fi

                # Reduce GPU mining to 10% (builds may need GPU for CUDA/heavy workloads)
                if systemctl is-active --quiet lolminer-nvidia; then
                    log "Limiting lolminer-nvidia to 10% CPU for builds"
                    systemctl set-property lolminer-nvidia.service CPUQuota="10%" --runtime
                fi

                if systemctl is-active --quiet lolminer-amd; then
                    log "Limiting lolminer-amd to 10% CPU for builds"
                    systemctl set-property lolminer-amd.service CPUQuota="10%" --runtime
                fi

                # Reduce CPU mining to 10% (builds need maximum CPU)
                if systemctl is-active --quiet xmrig; then
                    log "Limiting xmrig to 10% CPU for builds"
                    systemctl set-property xmrig.service CPUQuota="10%" --runtime
                fi

                # Ensure nix-daemon gets high priority for builds
                if systemctl is-active --quiet nix-daemon; then
                    log "Setting nix-daemon to high CPU weight for builds"
                    systemctl set-property nix-daemon.service CPUWeight=2048 --runtime
                fi

                echo "BUILDS profile applied: Mode: 10% mining, builds get priority"
            }

            apply_mining_profile() {
                echo "=== Applying GPU MINING profile ==="

                local gpus=$(get_gpu_list)
                local gpu_count=$(echo "$gpus" | wc -l)

                if [ "$gpu_count" -eq 0 ]; then
                    echo "WARNING: No NVIDIA GPUs detected"
                    return 0
                fi

                echo "Detected $gpu_count GPU(s) for mining profile"

                for gpu_id in $gpus; do
                    local gpu_name=$(get_gpu_name "$gpu_id")
                    echo "Configuring GPU $gpu_id ($gpu_name)..."

                    case "$gpu_name" in
                        *"3060"*)
                            # 3060 Ti: Efficiency-focused
                            nvidia_safe nvidia-smi -i "$gpu_id" -pl 100
                            nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1700
                            nvidia_safe nvidia-smi -i "$gpu_id" -lmc 5200
                            echo "  3060 Ti: 1700 MHz GPU, 5200 MHz mem, 100W limit"
                            ;;
                        *"3090"*)
                            # 3090: Efficiency with liquid cooling
                            nvidia_safe nvidia-smi -i "$gpu_id" -pl 270
                            nvidia_safe nvidia-smi -i "$gpu_id" -lgc 1750
                            nvidia_safe nvidia-smi -i "$gpu_id" -lmc 6500
                            echo "  3090: 1750 MHz GPU (liquid-cooled), 6500 MHz mem, 270W limit"
                            ;;
                        *)
                            # Default: Efficiency
                            nvidia_safe nvidia-smi -i "$gpu_id" -pl 200
                            nvidia_safe nvidia-smi -i "$gpu_id" -rgc
                            nvidia_safe nvidia-smi -i "$gpu_id" -rmc
                            echo "  $gpu_name: Default efficiency profile"
                            ;;
                    esac
                done

                echo "MINING profile applied: Mode: Efficiency-optimized"

                # Reset all mining to 100% CPU
                if systemctl is-active --quiet lolminer-nvidia; then
                    log "Resetting lolminer-nvidia to 100% CPU"
                    systemctl set-property lolminer-nvidia.service CPUQuota="100%" --runtime
                fi

                if systemctl is-active --quiet lolminer-amd; then
                    log "Resetting lolminer-amd to 100% CPU"
                    systemctl set-property lolminer-amd.service CPUQuota="100%" --runtime
                fi

                if systemctl is-active --quiet xmrig; then
                    local idle_threads=$(get_xmrig_idle_threads)
                    log "Resetting xmrig to 100% CPU ($idle_threads threads)"
                    systemctl set-property xmrig.service CPUQuota="100%" --runtime
                    reset_xmrig_threads "$idle_threads"
                fi

                # Start GPU mining if not running
                if ! systemctl is-active --quiet lolminer-nvidia; then
                    log "Starting lolminer-nvidia (no other workloads detected)"
                    systemctl start lolminer-nvidia
                fi
            }

            apply_idle_profile() {
                echo "=== Resetting GPUs to DEFAULT/AUTO profile ==="

                local gpus=$(get_gpu_list)
                local gpu_count=$(echo "$gpus" | wc -l)

                if [ "$gpu_count" -eq 0 ]; then
                    echo "WARNING: No NVIDIA GPUs detected"
                    return 0
                fi

                echo "Detected $gpu_count GPU(s), resetting to defaults"

                for gpu_id in $gpus; do
                    local gpu_name=$(get_gpu_name "$gpu_id")
                    echo "Resetting GPU $gpu_id ($gpu_name)..."

                    # Reset power limits based on GPU model
                    case "$gpu_name" in
                        *"3060"*)
                            nvidia_safe nvidia-smi -i "$gpu_id" -pl 200
                            ;;
                        *"3090"*)
                            nvidia_safe nvidia-smi -i "$gpu_id" -pl 350
                            ;;
                        *)
                            # Try to get max power limit
                            local max_power=$(nvidia-smi -i "$gpu_id" --query-gpu=power.max_limit --format=csv,noheader,nounits 2>/dev/null | tr -d '.' || echo "300")
                            nvidia_safe nvidia-smi -i "$gpu_id" -pl "''${max_power%.*}"
                            ;;
                    esac

                    # Reset locked clocks
                    nvidia_safe nvidia-smi -i "$gpu_id" -rgc
                    nvidia_safe nvidia-smi -i "$gpu_id" -rmc

                    echo "  GPU $gpu_id: Reset to defaults (adaptive mode)"
                done

                echo "RESET to defaults applied: Mode: Adaptive (auto)"
            }

            apply_profile() {
                local profile="$1"
                log "Applying profile: $profile"

                case "$profile" in
                    gaming)
                        apply_gaming_profile
                        ;;
                    ai)
                        apply_ai_profile
                        ;;
                    builds)
                        apply_builds_profile
                        ;;
                    mining)
                        apply_mining_profile
                        ;;
                    idle)
                        apply_idle_profile
                        ;;
                    *)
                        log "Unknown profile: $profile"
                        ;;
                esac
            }

            # State tracking
            CURRENT_WORKLOAD="idle"
            CHECK_INTERVAL=10  # Check every 10 seconds

            log "Starting GPU workload monitor (check interval: ''${CHECK_INTERVAL}s)"

            while true; do
                new_workload=$(get_workload_type)

                if [ "$new_workload" != "$CURRENT_WORKLOAD" ]; then
                    log "Workload changed: $CURRENT_WORKLOAD -> $new_workload"
                    CURRENT_WORKLOAD="$new_workload"
                    apply_profile "$new_workload"
                fi

                sleep "$CHECK_INTERVAL"
            done
          ''}/bin/compute-workload-monitor";
          Restart = "on-failure";
          RestartSec = "10s";
          # Allow access to nvidia-smi and systemd
          AmbientCapabilities = ["CAP_NET_ADMIN"];
        };
      };

      # ============================================================================
      # GAMEMODE INTEGRATION
      # ============================================================================
      # GameMode provides automatic detection when games start/stop
      # and runs our custom scripts to switch GPU profiles

      # ============================================================================
      # GPU PROFILE COMMANDS
      # ============================================================================
      # Convenient aliases for manual profile switching
      # NOTE: gpu-profile command merged with VR packages above to avoid duplicate assignment
    })
  ];
}

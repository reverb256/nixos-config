{
  pkgs,
  lib,
  ...
}: {
  hardware.gpu-compute = {
    enable = true;
    rocm.enable = true;
    vulkan.enable = true;
  };
  hardware.amdgpu.powerLimits = {
    enable = true;
    gpus = {
      "rx5600xt-0" = {
        index = 0;
        limit = 120;
      };
    };
  };

  hardware = {
    btrfs-compression.enable = true;
    monitoring = {
      enable = true;
      autoDetect = false;
      fanControl = false;
    };
    rgb-control = {
      enable = true;
      openrgb.enable = true;
      wraithRgb.enable = true;
      temperatureReactive = {
        enable = true;
        sensor = "cpu";
        thresholds = {
          cool = 45;
          warm = 60;
          hot = 70;
        };
        interval = 5;
      };
    };
  };

  boot.kernelModules = ["msr"];
  boot.kernelParams = lib.mkBefore [
    # AMD GPU Navi 10 stability: enable GPU recovery, lockup detection at 1s
    # Must come before mitigations to avoid being overridden
    "amdgpu.gpu_recovery=1"
    "amdgpu.noretry=0"
    "amdgpu.ppfeaturemask=0xfffd7fff"  # Disable Overdrive for stability
    "amdgpu.lockup_timeout=1000"
    "mitigations=auto"
  ];
  boot.extraModprobeConfig = ''
    # Force GPU recovery even if kernel params get lost
    options amdgpu gpu_recovery=1
    options amdgpu noretry=0
  '';

  environment = {
    variables = {
      LD_LIBRARY_PATH = lib.mkForce "${pkgs.rocmPackages.clr}/lib:${pkgs.rocmPackages.clr.icd}/lib:${pkgs.mesa.opencl}/lib";
      OCL_ICD_VENDORS = "/etc/OpenCL/vendors";
    };

    systemPackages = with pkgs; [
      rocmPackages.rocm-smi
      rocmPackages.rocminfo
    ];
  };

  systemd.tmpfiles.rules = let
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
    "R /var/lib/etcd - - - - -"
    "L+ /opt/rocm - - - - ${rocmEnv}"
    "L+ /opt/rocm/hip - - - - ${pkgs.rocmPackages.clr}"
  ];

  # Re-enable SMT — CachyOS kernel defaults to mitigations=auto,nosmt which
  # offlines all sibling threads. We override mitigations but the kernel
  # processes the first occurrence from initrd. This service re-enables SMT.
  systemd.services.enable-smt = {
    description = "Re-enable SMT (disabled by CachyOS kernel nosmt)";
    wantedBy = ["multi-user.target"];
    before = ["k3s.service"];
    serviceConfig.Type = "oneshot";
    script = ''
      if [ "$(cat /sys/devices/system/cpu/smt/control)" = "off" ]; then
        echo on > /sys/devices/system/cpu/smt/control
        # Online any offlined sibling threads
        for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
          if [ -f "$cpu/offline" ] && [ "$(cat "$cpu/offline")" = "1" ]; then
            echo 1 > "$cpu/online"
          fi
        done
      fi
    '';
  };

  # AMD GPU: force performance profile to prevent idle clock-gating hangs
  systemd.services.amdgpu-performance-profile = {
    description = "Set AMD GPU to performance profile (prevent idle clock-gating hangs)";
    wantedBy = ["multi-user.target"];
    after = ["systemd-udev-settle.service"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ''
        /bin/sh -c 'for c in /sys/class/drm/card*/device; do [ "$(cat "$c/vendor" 2>/dev/null)" = "0x1002" ] && echo high > "$c/power_dpm_force_performance_level" 2>/dev/null && break; done'
      '';
      RemainAfterExit = true;
    };
  };
}

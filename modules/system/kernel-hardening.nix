# Kernel Hardening Module
# Security-focused kernel parameters and settings from XNM1
{
  lib,
  config,
  ...
}: {
  options = {
    kernel-hardening = {
      zswap.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable zswap compressed swap (disable for older CPUs causing panics)";
      };
      zswap.maxPoolPercent = lib.mkOption {
        type = lib.types.int;
        default = 40;
        description = "Maximum RAM percentage for zswap pool (default 40, use 20 for older CPUs)";
      };
    };
  };

  config = {
    # ============================================================================
    # KERNEL SECURITY PARAMETERS (from XNM1)
    # ============================================================================
    security = {
      # Page table isolation for mitigation against side-channel attacks
      forcePageTableIsolation = true;

      # Allow unprivileged user namespaces (needed for Wayland, Podman, etc.)
      unprivilegedUsernsClone = true;

      # Flush L1 data cache on context switch (mitigation)
      virtualisation.flushL1DataCache = "cond";
    };

    # ============================================================================
    # KERNEL BOOT PARAMETERS
    # ============================================================================
    # Build the kernel params list first, then apply mkForce
    # This ensures mkForce is applied to the final list, not intermediate lists
    boot.kernelParams = let
      # Base parameters (always included)
      baseParams = [
        # Quiet boot with minimal output
        "quiet"
        "splash"
        "loglevel=3"
        "rd.udev.log_priority=3"
        "systemd.show_status=auto"

        # Console improvements
        "fbcon=nodefer"
        "vt.global_cursor_default=0"

        # Security: Disable kernel module loading after boot
        # WARNING: This prevents loading new modules until reboot
        # Comment out if you need to load modules dynamically (e.g., USB devices, virtualization)
        # "kernel.modules_disabled=1"

        # Linux Security Modules stack
        "lsm=landlock,lockdown,yama,integrity,apparmor,bpf"

        # Disable USB autosuspend (can cause issues with some devices)
        "usbcore.autosuspend=-1"

        # Video4Linux support
        "video4linux"

        # ACPI revision override for better hardware compatibility
        "acpi_rev_override=5"

        # ============================================================================
        # CRASH RECOVERY - Auto-reboot on hard lock to capture crash dump
        # ============================================================================
        # panic=10: Reboot after 10 seconds on kernel panic
        # panic_on_oops=1: Treat oops as panic (hard hang without logs)
        # softlockup_panic=1: Panic on soft lockup (process stuck in kernel)
        "panic=10"
        "panic_on_oops=1"
        "softlockup_panic=1"

        # ============================================================================
        # NMI WATCHDOG - Detect hard hangs
        # ============================================================================
        # nmi_watchdog=1 enables NMI watchdog for detecting hard CPU hangs
        "nmi_watchdog=1"
      ];

      # Conditional zswap parameters
      zswapParams =
        if config.kernel-hardening.zswap.enable
        then [
          "zswap.enabled=1"
          "zswap.compressor=zstd"
          "zswap.max_pool_percent=${builtins.toString config.kernel-hardening.zswap.maxPoolPercent}"
          "zswap.zpool=z3fold"
        ]
        else [
          "zswap.enabled=0"
        ];

      # Combine all parameters
      allParams = baseParams ++ zswapParams;
    in
      lib.mkForce allParams;

    # ============================================================================
    # KERNEL HUNG TASK DETECTION
    # ============================================================================
    boot.kernel.sysctl = {
      "vm.panic_on_oom" = 0; # Don't panic on OOM, let OOM killer do its job
      "kernel.hung_task_timeout_secs" = 120; # Detect tasks stuck for 120+ seconds
      "kernel.hung_task_warnings" = 10; # Warn up to 10 times before panic
      "kernel.softlockup_panic" = 1; # Panic on soft lockup (via boot param)
      "kernel.nmi_watchdog" = 1; # NMI watchdog enabled

      # Reverse path filtering - loose mode for VIP compatibility
      # Strict mode (1) drops packets arriving on unexpected interfaces
      # This breaks VIP traffic where return path differs from source path
      # Use mkForce to override security-hardening.nix strict mode
      "net.ipv4.conf.all.rp_filter" = lib.mkForce 2; # Loose mode
      "net.ipv4.conf.default.rp_filter" = lib.mkForce 2;
    };

    # ============================================================================
    # CRASH DUMP CAPTURE (kdump)
    # ============================================================================
    # Reserve memory for crash kernel. When main kernel crashes, kdump boots
    # into a minimal kernel to capture /proc/vmcore (crash dump)
    # Note: Requires 256M reserved memory at crash time
    # Note: kdump is not a kernel module - it's a userspace service that loads
    # a crash kernel. The makedumpfile package is needed for crash dump creation.
  };
}

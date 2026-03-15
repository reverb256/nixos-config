# Kernel Hardening Module
# Security-focused kernel parameters and settings from XNM1
{lib, ...}: {
  # ============================================================================
  # KERNEL SECURITY PARAMETERS (from XNM1)
  # ============================================================================

  # Page table isolation, user namespaces, L1 cache flush
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
  # Use mkForce to override NixOS defaults and prevent security-weakening duplicates
  boot.kernelParams = lib.mkForce [
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
    # ZSWAP - Compressed swap cache (better than traditional swap)
    # ============================================================================
    # Enables compressed swap in RAM (2:1 compression ratio = ~64GB effective)
    # Falls back to real swap on SSD when cache is full
    # Benefits: Faster than SSD swap, less SSD wear, better for AI/ML workloads
    "zswap.enabled=1"
    "zswap.compressor=zstd" # Best compression ratio (zstd > lzo > lz4)
    "zswap.max_pool_percent=40" # Use up to 40% of RAM for compressed swap (~12GB cache)
    "zswap.zpool=z3fold" # Better allocator than default zbud

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

  # ============================================================================
  # CRASH DUMP CAPTURE (kdump)
  # ============================================================================
  # Reserve memory for crash kernel. When main kernel crashes, kdump boots
  # into a minimal kernel to capture /proc/vmcore (crash dump)
  # Note: Requires 256M reserved memory at crash time
  # Note: kdump is not a kernel module - it's a userspace service that loads
  # a crash kernel. The makedumpfile package is needed for crash dump creation.
  # boot.kernel.sysctl."kernel.panic" = 10;  # Reboot after 10 seconds on panic
  # boot.kernelModules = ["kdump"]; # NOT a module - removed to prevent errors

  # ============================================================================
  # KERNEL HUNG TASK DETECTION
  # ============================================================================
  # Detect when tasks are stuck in D state (uninterruptible sleep)
  # This can indicate I/O deadlock or filesystem issues
  boot.kernel.sysctl = {
    "vm.panic_on_oom" = 0; # Don't panic on OOM, let OOM killer do its job
    "kernel.hung_task_timeout_secs" = 120; # Detect tasks stuck for 120+ seconds
    "kernel.hung_task_warnings" = 10; # Warn up to 10 times before panic
    "kernel.softlockup_panic" = 1; # Panic on soft lockup (via boot param)
    "kernel.nmi_watchdog" = 1; # NMI watchdog enabled

    # Reverse path filtering - loose mode for VIP compatibility
    # Strict mode (1) drops packets arriving on unexpected interfaces
    # This breaks VIP traffic where return path differs from source path
    "net.ipv4.conf.all.rp_filter" = 2; # Loose mode
    "net.ipv4.conf.default.rp_filter" = 2;
  };
}

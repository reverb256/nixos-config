# Kernel Hardening Module
# Security-focused kernel parameters and settings from XNM1
{...}: {
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
  boot.kernelParams = [
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
    "zswap.max_pool_percent=20" # Use up to 20% of RAM for compressed swap
    "zswap.zpool=z3fold" # Better allocator than default zbud
  ];
}

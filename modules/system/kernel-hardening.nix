# Kernel Hardening Module
# Security-focused kernel parameters and settings from XNM1
{pkgs, ...}: {
  # ============================================================================
  # KERNEL SECURITY PARAMETERS (from XNM1)
  # ============================================================================

  # Page table isolation for mitigation against side-channel attacks
  security.forcePageTableIsolation = true;

  # Allow unprivileged user namespaces (needed for Wayland, Podman, etc.)
  security.unprivilegedUsernsClone = true;

  # Flush L1 data cache on context switch (mitigation)
  security.virtualisation.flushL1DataCache = "cond";

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
  ];
}

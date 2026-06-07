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
    security = {
      forcePageTableIsolation = true;

      unprivilegedUsernsClone = true;

      virtualisation.flushL1DataCache = "cond";
    };

    boot.kernelParams = let
      baseParams = [
        "quiet"
        "splash"
        "loglevel=3"
        "rd.udev.log_priority=3"
        "systemd.show_status=auto"

        "fbcon=nodefer"
        "vt.global_cursor_default=0"

        "lsm=landlock,lockdown,yama,integrity,apparmor,bpf"

        "usbcore.autosuspend=-1"

        "video4linux"

        "acpi_rev_override=5"

        "panic=10"
        "panic_on_oops=1"
        "softlockup_panic=1"

        "nmi_watchdog=1"

        "processor.max_cstate=1"
        "intel_idle.max_cstate=1"
        "iommu=pt"
      ];

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

      allParams = baseParams ++ zswapParams;
    in
      allParams;

    boot.kernel.sysctl = {
      "vm.panic_on_oom" = 0;
      "kernel.hung_task_timeout_secs" = 120;
      "kernel.hung_task_warnings" = 10;
      "kernel.softlockup_panic" = 1;
      "kernel.nmi_watchdog" = 1;

      "net.ipv4.conf.all.rp_filter" = lib.mkForce 2;
      "net.ipv4.conf.default.rp_filter" = lib.mkForce 2;
    };
    # Disable jitterentropy service — CachyOS kernel seccomp kills it with SIGSYS.
    # The kernel RNG provides sufficient entropy (256+ avail); this userspace
    # daemon is redundant and crashes on every boot.
    systemd.services.jitterentropy.enable = false;
  };
}

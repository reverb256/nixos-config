{lib, ...}: {
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 12;
    freeSwapThreshold = 10;
    enableNotifications = true;
  };

  # Override compute-market flake's hugepage allocations (hugepagesz=1G hugepages=3).
  # Kernel processes cmdline left-to-right; last value wins.
  # mkAfter ensures these come after compute-market's params in the final list.
  # BOTH 1G and 2M pools must be explicitly zeroed — the kernel only zeros the
  # pool matching the current hugepagesz.  vm.nr_hugepages alone is insufficient
  # because it only controls the default pool (which becomes 1G after hugepagesz=1G).
  boot.kernelParams = lib.mkAfter [
    "hugepagesz=1G"
    "hugepages=0"
    "hugepagesz=2M"
    "hugepages=0"
  ];

  # Safety net: ensure both hugepage pools stay zeroed at boot via tmpfiles.
  # The kernel cmdline should handle it, but in case it doesn't, this runs
  # early in boot and explicitly writes 0 to both pools.
  systemd.tmpfiles.rules = [
    "w /sys/kernel/mm/hugepages/hugepages-1048576kB/nr_hugepages - - - - 0"
    "w /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages - - - - 0"
  ];

  # Post-boot watchdog: 2MB hugepages can be re-allocated by kubelet/k3s after
  # tmpfiles runs.  Timer fires every 30s to keep both pools at 0.
  systemd.services.zero-hugepages = {
    description = "Zero hugepage pools";
    serviceConfig.Type = "oneshot";
    script = ''
      echo 0 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages 2>/dev/null
    '';
  };
  systemd.timers.zero-hugepages = {
    description = "Periodic hugepage pool zeroing";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "5s";
      OnUnitActiveSec = "30s";
      AccuracySec = "1s";
    };
  };

  boot.kernel.sysctl = {
    "vm.nr_hugepages" = lib.mkForce 0;
    "vm.overcommit_memory" = lib.mkForce 0;
    "vm.overcommit_ratio" = lib.mkDefault 100;

    "vm.min_free_kbytes" = lib.mkDefault 1048576;

    "vm.swappiness" = lib.mkForce 60;

    "vm.dirty_ratio" = lib.mkForce 10;
    "vm.dirty_background_ratio" = lib.mkForce 5;

    "vm.vfs_cache_pressure" = lib.mkForce 150;

    "vm.page-cache-limit" = lib.mkForce 1073741824;

    "vm.page-cluster" = lib.mkForce 3;

    "vm.watermark_scale_factor" = lib.mkForce 150;

    "vm.extra_free_kbytes" = lib.mkForce 524288;
  };

  boot.kernel.sysctl."kernel.core_pattern" = "/dev/null";
}

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
  boot.kernelParams = lib.mkAfter [
    "hugepagesz=1G"
    "hugepages=0"
  ];

  boot.kernel.sysctl = {
    "vm.nr_hugepages" = lib.mkForce 0;
    "vm.overcommit_memory" = lib.mkForce 0;
    "vm.overcommit_ratio" = lib.mkDefault 100;

    "vm.min_free_kbytes" = lib.mkDefault 1048576;

    "vm.swappiness" = lib.mkForce 10;

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

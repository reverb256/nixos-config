{lib, ...}: {
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 12;
    freeSwapThreshold = 10;
    enableNotifications = true;
  };

  boot.kernel.sysctl = {
    "vm.overcommit_memory" = lib.mkForce 0;
    "vm.overcommit_ratio" = lib.mkDefault 100;

    "vm.min_free_kbytes" = lib.mkDefault 1048576;

    "vm.swappiness" = lib.mkForce 60;

    "vm.dirty_ratio" = lib.mkForce 10;
    "vm.dirty_background_ratio" = lib.mkForce 5;

    "vm.vfs_cache_pressure" = lib.mkForce 150;


    "vm.page-cluster" = lib.mkForce 3;

    "vm.watermark_scale_factor" = lib.mkForce 150;

  };

  boot.kernel.sysctl."kernel.core_pattern" = "/dev/null";
}
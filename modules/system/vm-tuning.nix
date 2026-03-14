{lib, ...}: {
  # ============================================================================
  # VM TUNING - Memory pressure defense and OOM prevention
  # ============================================================================
  # 2026-03-13: Updated to prevent crashes from memory pressure
  # Context: 32GB RAM system with Zswap enabled (20% pool = 6.4GB)

  boot.kernel.sysctl = {
    # ========================================================================
    # OVERCOMMIT CONTROL - Prevent "always overcommit" behavior
    # ========================================================================
    # Mode 0 (default): Heuristic overcommit - denies obviously bogus requests
    # Mode 1: ALWAYS overcommit - dangerous, causes OOM crashes
    # Mode 2: Strict overcommit - fails allocations exceeding swap + RAM
    #
    # Use mkForce to prevent other modules from overriding to mode 1
    "vm.overcommit_memory" = lib.mkForce 0; # Heuristic (safe)
    "vm.overcommit_ratio" = lib.mkDefault 100; # Allow reasonable overcommit

    # ========================================================================
    # MIN FREE KBYTES - Reserve memory to prevent allocation deadlock
    # ========================================================================
    # Kernel needs free pages for atomic allocations. If too low, system
    # deadlocks trying to reclaim memory while needing memory to reclaim.
    #
    # Formula: max(128MB, 3% of RAM) for desktop systems
    # For 32GB: 3% = 983MB, round to 1GB for safety margin
    "vm.min_free_kbytes" = lib.mkForce 1048576; # 1GB reserved (~3% of 32GB)

    # ========================================================================
    # SWAPPINESS - Balance cache vs swap with Zswap enabled
    # ========================================================================
    # Default 60 is too aggressive with Zswap. Lower value prefers:
    # - Keeping anonymous pages in RAM
    # - Using Zswap pool first (20% RAM = 6.4GB)
    # - Only swap to SSD when Zswap is full
    #
    # 20-25 is optimal for Zswap systems with high memory pressure
    # Increased from 15 to 20 to reduce pressure spikes and direct reclaim
    # 1 = minimal swap, 100 = aggressive swap
    "vm.swappiness" = lib.mkForce 20; # Balanced - reduces PSI pressure spikes

    # ========================================================================
    # VFS CACHE PRESSURE - Controls kernel cache reclaim priority
    # ========================================================================
    # Default 100 aggressively reclaims inode/dentry cache
    # Higher = reclaim cache more, lower = reclaim cache less
    # 75 is better for desktop workloads with many file operations
    "vm.vfs_cache_pressure" = lib.mkForce 75;

    # ========================================================================
    # PAGE CACHE LIMITS - Prevent page cache from crowding anonymous memory
    # ========================================================================
    # Limit page cache to prevent it from consuming all memory
    # Helps keep working sets in RAM under memory pressure
    "vm.page-cache-limit" = lib.mkDefault 0; # Disable (use default for now)
  };
}

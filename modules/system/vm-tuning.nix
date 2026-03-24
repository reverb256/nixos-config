{lib, ...}: {
  # ============================================================================
  # VM TUNING - Memory pressure defense and OOM prevention
  # ============================================================================
  # 2026-03-15: Updated for heavy build/mining workloads
  # Context: 32GB RAM system with Zswap enabled (40% pool = 12GB)
  # - Increased zswap pool for better compressed swap caching
  # - Earlier swappiness to prevent emergency thrashing
  # - earlyoom as last resort against death spirals

  # ============================================================================
  # EARLYOOM - OOM prevention daemon (nuclear option)
  # ============================================================================
  # Kills processes before system thrashes to death
  # Better to OOM one process than freeze entire system for hours
  # PSI-based: triggers when memory pressure is sustained
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 12; # Kill at 12% RAM free (~3.8GB) - allows Genshin Impact (3.7GB) to launch
    freeSwapThreshold = 10; # Kill at 10% swap free (~3.2GB)
    enableNotifications = true; # Notify user before killing
  };

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
    # - Using Zswap pool first (40% RAM = 12GB with increased pool)
    # - Only swap to SSD when Zswap is full
    #
    # 40 is optimal for Zswap systems with variable memory pressure:
    # - Earlier, more gradual swapping vs emergency thrashing
    # - Trades background swapping for panic-driven swap storms
    # - 1 = minimal swap, 100 = aggressive swap
    "vm.swappiness" = lib.mkForce 40; # Earlier swap = smoother than thrashing

    # ========================================================================
    # DIRTY MEMORY CAPS - Limit pending write cache
    # ========================================================================
    # Prevents dirty pages (pending disk writes) from consuming all RAM
    # Default: dirty_ratio=20 (6.5GB), dirty_background_ratio=10 (3.2GB)
    # Lower values = more frequent writeback, less memory pressure
    "vm.dirty_ratio" = lib.mkForce 10; # Max 10% RAM before forced writeback (~3.2GB)
    "vm.dirty_background_ratio" = lib.mkForce 5; # Start writeback at 5% RAM (~1.6GB)

    # ========================================================================
    # VFS CACHE PRESSURE - Controls kernel cache reclaim priority
    # ========================================================================
    # Default 100 aggressively reclaims inode/dentry cache
    # Higher = reclaim cache more, lower = reclaim cache less
    # 150 is more aggressive - frees slab cache faster under memory pressure
    "vm.vfs_cache_pressure" = lib.mkForce 150;

    # ========================================================================
    # PAGE CACHE LIMITS - Prevent page cache from crowding anonymous memory
    # ========================================================================
    # Limit page cache to prevent it from consuming all memory
    # Helps keep working sets in RAM under memory pressure
    "vm.page-cache-limit" = lib.mkForce 1073741824; # 1GB cap (was: disabled)

    # ========================================================================
    # PAGE CLUSTER - Swap read-ahead performance
    # ========================================================================
    # Controls how many pages are read ahead from swap at once
    # Default 2 (32 pages), increase to 3 (64 pages) for better swap throughput
    # Helps when system reads back swapped-out pages
    "vm.page-cluster" = lib.mkForce 3; # Read ahead 64 pages from swap

    # ========================================================================
    # WATERMARK SCALE FACTOR - More proactive memory reclaim
    # ========================================================================
    # Controls when kernel starts reclaiming memory before hitting hard limits
    # Default 10 (very low), 150 = start reclaiming earlier and more gradually
    # Prevents "all at once" reclaim storms that cause system freezes
    "vm.watermark_scale_factor" = lib.mkForce 150; # Start reclaim earlier

    # ========================================================================
    # EXTRA FREE KBYTES - Additional memory headroom
    # ========================================================================
    # Extra free memory the kernel tries to keep available
    # Reduces allocation latency under memory pressure
    # 512MB = comfortable buffer for desktop workloads
    "vm.extra_free_kbytes" = lib.mkForce 524288; # 512MB extra free
  };
}

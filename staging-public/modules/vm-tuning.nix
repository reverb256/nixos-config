{ config, lib, ... }: {
  # ============================================================================
  # VM TUNING - Fix memory overcommit issues causing Discover crashes
  # ============================================================================
  
  # Fix memory allocation failures in Discover and other Qt applications
  # Issue: strict overcommit (mode 2) prevents memory allocation even with swap available
  # Solution: Use heuristic overcommit with 100% ratio (default behavior)
  boot.kernel.sysctl = {
    "vm.overcommit_memory" = lib.mkDefault 0;  # Heuristic overcommit (default: 0)
    "vm.overcommit_ratio" = lib.mkDefault 100; # Allow full overcommit (default: 50)
  };
}
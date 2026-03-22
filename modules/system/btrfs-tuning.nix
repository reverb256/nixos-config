# BTRFS Tuning - Reduce memory overhead and improve performance
# Applies to all BTRFS filesystems cluster-wide
{ config, lib, ... }: {
  # ============================================================================
  # BTRFS TUNING - Commit interval and memory optimizations
  # ============================================================================
  # Default commit=30s causes frequent metadata writes, increasing RAM usage
  # Longer intervals reduce memory pressure and improve SSD longevity
  #
  # Trade-off: Up to 30 seconds of data loss on power failure (acceptable for
  # cluster with UPS and regular backups to Garage S3)
  boot.kernelParams = [
    # Increase BTRFS commit interval from default 30s to 300s (5 minutes)
    # Reduces metadata memory usage and write amplification
    "btrfs.commit_interval=300"
  ];
}

# ZRAM Swap and Kernel Network Tuning
#
# Reusable module for ZRAM compressed swap configuration and kernel sysctl
# tuning for network buffers and reverse path filtering.
#
# Extracted from host-specific configs to allow consistent tuning across nodes.
#
# Usage:
#   services.zram-tuning = {
#     enable = true;
#     zram.algorithm = "zstd";
#     zram.memoryPercent = 25;
#     network.enable = true;  # kernel network buffer tuning
#   };
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.zram-tuning;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
in
{
  options.services.zram-tuning = {
    enable = mkEnableOption "ZRAM swap and kernel tuning";

    zram = {
      algorithm = mkOption {
        type = types.str;
        default = "zstd";
        description = "Compression algorithm for ZRAM (zstd, lz4, lzo-rle)";
      };

      memoryPercent = mkOption {
        type = types.int;
        default = 25;
        description = "Percentage of RAM to use for ZRAM swap";
      };

      priority = mkOption {
        type = types.int;
        default = 999;
        description = "Swap priority (higher = preferred over disk swap)";
      };
    };

    network = {
      enable = mkEnableOption "Kernel network buffer tuning";

      rmemDefault = mkOption {
        type = types.int;
        default = 262144;
        description = "Default receive buffer size in bytes (256KB default)";
      };

      wmemDefault = mkOption {
        type = types.int;
        default = 262144;
        description = "Default send buffer size in bytes (256KB default)";
      };

      rmemMax = mkOption {
        type = types.int;
        default = 16777216;
        description = "Maximum receive buffer size in bytes (16MB default)";
      };

      wmemMax = mkOption {
        type = types.int;
        default = 16777216;
        description = "Maximum send buffer size in bytes (16MB default)";
      };

      rpFilter = mkOption {
        type = types.int;
        default = 1;
        description = "Reverse path filtering (1 = strict, required for Calico BGP)";
      };
    };
  };

  config = mkIf cfg.enable {
    # ZRAM compressed swap — reduces SSD wear, faster than disk swap
    zramSwap = {
      enable = true;
      algorithm = cfg.zram.algorithm;
      memoryPercent = cfg.zram.memoryPercent;
      priority = cfg.zram.priority;
    };

    # Kernel network buffer tuning (frees unused socket buffers)
    boot.kernel.sysctl = mkIf cfg.network.enable {
      "net.core.rmem_default" = cfg.network.rmemDefault;
      "net.core.wmem_default" = cfg.network.wmemDefault;
      "net.core.rmem_max" = cfg.network.rmemMax;
      "net.core.wmem_max" = cfg.network.wmemMax;

      # Reverse path filtering for BGP (Calico CNI requirement)
      "net.ipv4.conf.all.rp_filter" = cfg.network.rpFilter;
    };
  };
}

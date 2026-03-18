# Redis/Valkey Configuration for SearXNG Caching
# Provides persistent, distributed caching for multi-instance SearXNG deployment

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.redis.servers.searxng;
in
{
  options.services.redis.servers.searxng = {
    enable = mkEnableOption "Redis server for SearXNG caching";

    bind = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "IP address to bind Redis server";
    };

    port = mkOption {
      type = types.port;
      default = 6379;
      description = "Port to listen on";
    };

    maxmemory = mkOption {
      type = types.str;
      default = "256mb";
      description = "Maximum memory to use for caching";
    };

    maxmemoryPolicy = mkOption {
      type = types.str;
      default = "allkeys-lru";
      description = "Eviction policy when maxmemory is reached";
    };
  };

  config = mkIf cfg.enable {
    services.redis.servers.searxng = {
      inherit (cfg) enable bind port maxmemory maxmemoryPolicy;

      # Performance tuning for AI workloads
      databases = 1;
      save = [];  # Disable RDB snapshots for pure cache use
      appendonly = false;  # Disable AOF for cache (faster)

      # Security
      requirePass = false;  # No password for local use
      unixSocket = "/run/redis-searxng/redis.sock";

      # Logging
      logLevel = "warning";

      # Advanced settings
      settings = {
        # Memory management
        maxmemory-policy = cfg.maxmemoryPolicy;

        # Connection settings
        tcp-backlog = 511;
        timeout = 0;
        tcp-keepalive = 300;

        # Performance
        # Use more memory for hash tables
        hash-max-ziplist-entries = 512;
        hash-max-ziplist-value = 64;

        # Disable persistence for pure caching
        save = "";

        # Maximum clients
        maxclients = 10000;

        # Slow log
        slowlog-log-slower-than = 10000;  # 10ms
        slowlog-max-len = 128;

        # Latency monitoring
        latency-monitor-threshold = 100;  # ms
      };
    };

    # systemd tmpfiles for Unix socket
    systemd.tmpfiles.rules = [
      "d /run/redis-searxng 0750 redis redis -"
    ];

    # Ensure Redis starts before SearXNG (if using systemd)
    # Note: Our SearXNG runs in Docker, so this is informational
  };
}

# Dual XMRig Module - Always-on + Pause-able Instances
# Two XMRig processes for flexible mining during gaming
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.mining.xmrigDual;
  hostname = config.networking.hostName;
  defaultWallet = "krxXVNVMM7.${hostname}";

  # XMRig wrapper script - reads API token and passes to xmrig
  mkXmrigWrapper = name: port: tokenFile: threads: pkgs.writeShellScript "xmrig-wrapper-${name}" ''
    PATH=/run/current-system/sw/bin:$PATH
    TOKEN_FILE="${tokenFile}"
    RUNTIME_CONFIG="/run/xmrig-${name}/config.json"

    # Use runtime config with token if available, otherwise fallback to default config
    CONFIG="''${RUNTIME_CONFIG:-/etc/xmrig-${name}/config.json}"

    if [ -r "$CONFIG" ]; then
      exec ${pkgs.xmrig}/bin/xmrig -c "$CONFIG" --randomx-1gb-pages --threads=${toString threads}
    else
      exec ${pkgs.xmrig}/bin/xmrig -c /etc/xmrig-${name}/config.json --randomx-1gb-pages --threads=${toString threads}
    fi
  '';

  # Generate XMRig config for a specific instance
  mkXmrigConfig = name: port: pool: wallet: password: tls: threads: builtins.toJSON {
    api = {
      id = null;
      worker-id = "${hostname}-${name}";
    };
    http = {
      enabled = true;
      host = "127.0.0.1";
      port = port;
      restricted = false;
    };
    pools = [
      {
        url = pool;
        user = wallet;
        pass = password;
        tls = tls;
        keepalive = true;
        nicehash = false;
      }
    ];
    randomx = {
      "1gb-pages" = true;
      mode = "fast";
    };
    asm = true;
    cpu = {
      enabled = true;
      "huge-pages" = true;
      "huge-pages-jit" = false;
      "hw-aes" = null;
      priority = null;
      "memory-pool" = false;
      yield = true;
      inherit threads;
    };
    logging = {
      type = "stdout";
      level = "0";
    };
  };

  # Helper to create ExecStartPre for token injection
  mkExecStartPre = name: tokenFile: pkgs.writeShellScript "xmrig-config-prep-${name}" ''
    TOKEN_FILE="${tokenFile}"
    CONFIG_DIR=/run/xmrig-${name}

    mkdir -p "$CONFIG_DIR"

    if [ -r "$TOKEN_FILE" ]; then
      TOKEN=$(cat "$TOKEN_FILE")
      ${pkgs.jq}/bin/jq ".http.\"access-token\" = \"$TOKEN\"" /etc/xmrig-${name}/config.json > "$CONFIG_DIR/config.json"
    else
      cp /etc/xmrig-${name}/config.json "$CONFIG_DIR/config.json"
    fi

    chmod 640 "$CONFIG_DIR/config.json"
  '';

  # Host-specific thread allocations
  getAlwaysOnThreads = host: {
    zephyr = 4;   # 12% of 32 cores
    nexus = 4;    # 17% of 24 cores
    sentry = 4;   # 25% of 16 cores
  }.${host} or 4;

  getFlexibleThreads = host: {
    zephyr = 12;  # 38% of 32 cores (total 50% with always-on)
    nexus = 8;    # 33% of 24 cores (total 50% with always-on)
    sentry = 4;   # 25% of 16 cores (total 50% with always-on)
  }.${host} or 8;
in {
  options.services.mining.xmrigDual = {
    enable = mkEnableOption "Dual XMRig Services (always-on + pause-able)";

    alwaysOn = {
      enable = mkEnableOption "Always-on XMRig instance";
      threads = mkOption {
        type = types.int;
        default = getAlwaysOnThreads hostname;
        description = "Thread count for always-on instance (defaults to host-specific)";
      };
      httpPort = mkOption {
        type = types.int;
        default = 8081;
        description = "HTTP API port for always-on instance";
      };
      httpTokenFile = mkOption {
        type = types.path;
        default = "/run/agenix/xmrig-always-api-token";
        description = "Path to HTTP API token file for always-on instance";
      };
      autostart = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to start always-on instance at boot";
      };
    };

    flexible = {
      enable = mkEnableOption "Flexible (pause-able) XMRig instance";
      threads = mkOption {
        type = types.int;
        default = getFlexibleThreads hostname;
        description = "Thread count for flexible instance (defaults to host-specific)";
      };
      httpPort = mkOption {
        type = types.int;
        default = 8082;
        description = "HTTP API port for flexible instance";
      };
      httpTokenFile = mkOption {
        type = types.path;
        default = "/run/agenix/xmrig-flexible-api-token";
        description = "Path to HTTP API token file for flexible instance";
      };
      autostart = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to start flexible instance at boot";
      };
    };

    # Common settings (shared by both instances)
    pool = mkOption {
      type = types.str;
      default = "xtm-rx-us.kryptex.network:8038";
    };
    wallet = mkOption {
      type = types.str;
      default = defaultWallet;
    };
    password = mkOption {
      type = types.str;
      default = "x";
    };
    tls = mkOption {
      type = types.bool;
      default = true;
    };
  };

  config = mkIf cfg.enable {
    # Ensure base mining module is enabled
    services.mining.enable = true;

    # Runtime directories for both instances
    systemd.tmpfiles.rules = [
      "d /run/xmrig-always 0750 mining mining - -"
      "d /run/xmrig-flexible 0750 mining mining - -"
    ];

    # Configuration files for both instances
    environment.etc = {
      "xmrig-always/config.json" = mkIf cfg.alwaysOn.enable {
        text = mkXmrigConfig "always" cfg.alwaysOn.httpPort cfg.pool cfg.wallet cfg.password cfg.tls cfg.alwaysOn.threads;
      };
      "xmrig-flexible/config.json" = mkIf cfg.flexible.enable {
        text = mkXmrigConfig "flexible" cfg.flexible.httpPort cfg.pool cfg.wallet cfg.password cfg.tls cfg.flexible.threads;
      };
    };

    # Firewall rules for API ports
    networking.firewall.interfaces.lo.allowedTCPPorts = [
      cfg.alwaysOn.httpPort
      cfg.flexible.httpPort
    ];

    # Systemd services for both instances
    systemd.services = {
      xmrig-always = mkIf cfg.alwaysOn.enable {
        description = "XMRig CPU Mining - Always-on Instance";
        wantedBy = mkIf cfg.alwaysOn.autostart ["multi-user.target"];
        after = ["network.target"];
        serviceConfig = {
          User = "mining";
          Group = "mining";
          Slice = "mining.slice";
          ExecStartPre = mkExecStartPre "always" cfg.alwaysOn.httpTokenFile;
          ExecStart = mkXmrigWrapper "always" cfg.alwaysOn.httpPort cfg.alwaysOn.httpTokenFile cfg.alwaysOn.threads;
          Restart = "always";
          NoNewPrivileges = false;
          PrivateTmp = true;
          ProtectKernelTunables = false;
          ProtectControlGroups = true;
          ProtectHostname = true;
          RestrictRealtime = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadOnlyPaths = "/";
          ReadWritePaths = [
            "/var/lib/mining"
            "/var/log/mining"
            "/run/xmrig-always"
          ];
          LimitMEMLOCK = "4G";
          CapabilityBoundingSet = "CAP_SYS_RAWIO";
          AmbientCapabilities = "CAP_SYS_RAWIO";
        };
      };

      xmrig-flexible = mkIf cfg.flexible.enable {
        description = "XMRig CPU Mining - Flexible (pause-able) Instance";
        wantedBy = mkIf cfg.flexible.autostart ["multi-user.target"];
        after = ["network.target"];
        serviceConfig = {
          User = "mining";
          Group = "mining";
          Slice = "mining.slice";
          ExecStartPre = mkExecStartPre "flexible" cfg.flexible.httpTokenFile;
          ExecStart = mkXmrigWrapper "flexible" cfg.flexible.httpPort cfg.flexible.httpTokenFile cfg.flexible.threads;
          Restart = "always";
          NoNewPrivileges = false;
          PrivateTmp = true;
          ProtectKernelTunables = false;
          ProtectControlGroups = true;
          ProtectHostname = true;
          RestrictRealtime = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadOnlyPaths = "/";
          ReadWritePaths = [
            "/var/lib/mining"
            "/var/log/mining"
            "/run/xmrig-flexible"
          ];
          LimitMEMLOCK = "4G";
          CapabilityBoundingSet = "CAP_SYS_RAWIO";
          AmbientCapabilities = "CAP_SYS_RAWIO";
        };
      };
    };

    # Update mining target to include both instances
    systemd.targets.mining.wants = mkMerge [
      (mkIf cfg.alwaysOn.enable ["xmrig-always.service"])
      (mkIf cfg.flexible.enable ["xmrig-flexible.service"])
    ];
  };
}

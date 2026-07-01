{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.peakminer;
  inherit (lib) mkEnableOption mkOption types mkIf;

  # Stratum auth translator proxy — rewrites peakminer's named-params authorize
  # to standard array-form so the pool sees "WALLET.WORKER" as the login string.
  # This makes the Kryptex dashboard display per-worker names.
  # Shares still flow through peakminer's working named-params path internally;
  # the proxy is transparent for mining.submit and all other messages.
  authTranslator = pkgs.writeScript "stratum-auth-translator.py" (builtins.readFile ../scripts/stratum-auth-translator.py);
in {
  options.services.peakminer = {
    enable = mkEnableOption "PeakMiner GPU mining (Pearl/PRL)";

    instances = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Service name suffix and pool worker name (e.g. forge-4060-0)";
          };
          wallet = mkOption {
            type = types.str;
            description = "Wallet address WITHOUT worker suffix (e.g. krxXVNVMM7). The worker name is derived from the 'name' field.";
          };
          pools = mkOption {
            type = types.listOf types.str;
            default = ["stratum+tcp://prl.kryptex.network:7048"];
            description = "Upstream pool URLs (the REAL pool, not the local proxy). Scheme REQUIRED.";
          };
          devices = mkOption {
            type = types.str;
            default = "all";
            description = "GPU device indices: all or comma-separated (e.g. 0,1)";
          };
          powerLimit = mkOption {
            type = types.nullOr types.int;
            default = null;
            description = "GPU power limit in watts (null = no change)";
          };
          gpuId = mkOption {
            type = types.int;
            default = 0;
            description = "NVIDIA GPU device index for nvidia-smi power limit";
          };
          apiPort = mkOption {
            type = types.port;
            default = 4068;
            description = "HTTP stats API port";
          };
          tempStop = mkOption {
            type = types.nullOr types.int;
            default = null;
            description = "Pause GPU at this temperature (°C)";
          };
          fanSpeed = mkOption {
            type = types.nullOr types.int;
            default = null;
            description = "Fixed fan speed 0-100% (null = auto control)";
          };
          fanTarget = mkOption {
            type = types.nullOr types.int;
            default = 65;
            description = "Target temperature for closed-loop fan control (°C)";
          };
          fanMin = mkOption {
            type = types.nullOr types.int;
            default = 30;
            description = "Minimum fan duty cycle (0-100%) for closed-loop control";
          };
          fanMax = mkOption {
            type = types.nullOr types.int;
            default = 100;
            description = "Maximum fan duty cycle (0-100%) for closed-loop control";
          };
          proxyPort = mkOption {
            type = types.port;
            description = "Local port for the auth translator proxy. PeakMiner connects here instead of the real pool.";
          };
          extraArgs = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Extra peakminer CLI arguments.";
          };
        };
      });
      default = [];
      description = "List of PeakMiner instances";
    };

    user = mkOption {
      type = types.str;
      default = "root";
      description = "User to run miner as (root needed for OC/power control)";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.all (i:
          lib.all (url: lib.hasPrefix "stratum+" url) i.pools
        ) cfg.instances;
        message = "services.peakminer: every instance pool URL must begin with stratum+tcp:// or stratum+ssl://";
      }
      {
        assertion = lib.all (i: !lib.hasInfix "." i.wallet) cfg.instances;
        message = "services.peakminer: wallet must NOT contain a dot (worker suffix is added by the auth translator proxy from the 'name' field)";
      }
    ];

    systemd.services = lib.foldl' (acc: instance:
      let
        # Parse the first pool URL to get host:port for the proxy upstream
        poolUrl = builtins.head instance.pools;
        # Strip stratum+tcp:// or stratum+ssl:// prefix
        poolAddr = lib.removePrefix "stratum+tcp://" (lib.removePrefix "stratum+ssl://" poolUrl);
        # Split host:port
        poolParts = lib.splitString ":" poolAddr;
        poolHost = builtins.head poolParts;
        poolPortStr = if builtins.length poolParts > 1 then builtins.elemAt poolParts 1 else "7048";

        powerLimitArgs =
          if instance.powerLimit != null
          then "+/run/current-system/sw/bin/nvidia-smi -i ${toString instance.gpuId} -pl ${toString instance.powerLimit}"
          else "";
        tempArg =
          if instance.tempStop != null
          then ["--gpu-temp-stop ${toString instance.tempStop}"]
          else [];
        fanArg =
          if instance.fanSpeed != null
          then ["--gpu-fan ${toString instance.fanSpeed}"]
          else [
            "--gpu-fan-target ${toString instance.fanTarget}"
            "--gpu-fan-min ${toString instance.fanMin}"
            "--gpu-fan-max ${toString instance.fanMax}"
          ];

        # Auth translator proxy service
        proxyService = {
          name = "peakminer-proxy-${instance.name}";
          value = {
            description = "Stratum auth translator for ${instance.name}";
            wantedBy = ["multi-user.target"];
            after = ["network-online.target"];
            wants = ["network-online.target"];
            serviceConfig = {
              Type = "simple";
              ExecStart = "${pkgs.python3}/bin/python3 ${authTranslator} ${poolHost} ${poolPortStr} ${toString instance.proxyPort} ${instance.name}";
              Restart = "always";
              RestartSec = 5;
            };
          };
        };

        # PeakMiner service — connects to the LOCAL proxy, not the real pool
        minerService = {
          name = "peakminer-${instance.name}";
          value = {
            description = "PeakMiner - ${instance.name}";
            wantedBy = ["multi-user.target"];
            after = ["network-online.target" "peakminer-proxy-${instance.name}.service"];
            wants = ["network-online.target"];
            requires = ["peakminer-proxy-${instance.name}.service"];

            serviceConfig = {
              Type = "simple";
              User = cfg.user;
              ExecStartPre = lib.mkIf (instance.powerLimit != null) (
                lib.mkBefore powerLimitArgs
              );
              ExecStartPost = lib.mkIf (instance.powerLimit != null) (
                "+/run/current-system/sw/bin/nvidia-smi -i ${toString instance.gpuId} -pl ${toString instance.powerLimit}"
              );
              ExecStart = pkgs.writeShellScript "peakminer-${instance.name}" ''
                export CUDA_DEVICE_ORDER=PCI_BUS_ID
                export LD_LIBRARY_PATH=/run/opengl-driver/lib:''${LD_LIBRARY_PATH:-}
                exec ${pkgs.peakminer}/bin/peakminer \
                  --coin pearl \
                  --url stratum+tcp://127.0.0.1:${toString instance.proxyPort} \
                  --user ${instance.wallet} \
                  --worker ${instance.name} \
                  --devices ${instance.devices} \
                  --api-port ${toString instance.apiPort} \
                  ${lib.concatStringsSep " " tempArg} \
                  ${lib.concatStringsSep " " fanArg} \
                  ${lib.concatStringsSep " " instance.extraArgs}
              '';
              Restart = "always";
              RestartSec = 10;
            };
          };
        };
      in
        acc // (lib.listToAttrs [proxyService minerService])
    ) {} cfg.instances;
  };
}

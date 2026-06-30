{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.peakminer;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.peakminer = {
    enable = mkEnableOption "PeakMiner GPU mining (Pearl/PRL)";

    instances = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Service name suffix (e.g. forge-4060-0)";
          };
          wallet = mkOption {
            type = types.str;
            description = "Wallet formatted as krxXVNVMM7.<name>";
          };
          pools = mkOption {
            type = types.listOf types.str;
            # Working default at 2026-06-29: plaintext (7048) + --legacy-auth.
            # Per peakminer --help: -L/--legacy-auth forces `["user","password"]`
            # array-form authorize; combined with TCP/7048 this is the Kryptex
            # Stratum V1 path the cluster has actually been mining on since May.
            # TLS on 8048 silently rejected shares (even with --legacy-auth) so
            # we keep plaintext until Kryptex documents an SSL endpoint.
            # 2026-06-30: collapsed to single `prl` endpoint per operator directive
            # (TLS 8048 broken; fallback `prl-us` mirror removed). If Kryptex
            # ever exposes additional endpoints, list them here in failover order.
            # --legacy-auth rationale lives in tests/peakminer.nix::legacyAuthInDefault.
            default = ["stratum+tcp://prl.kryptex.network:7048"];
            description = "List of pool URLs. Currently single-primary; expand to a list if a failover is added. Scheme REQUIRED (stratum+tcp:// or stratum+ssl://host:port).";
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
          legacyAuth = mkOption {
            type = types.bool;
            # 2026-06-30 verification (all 5 GPUs tested over 30+ min each):
            # ┃  version   ┃ --legacy-auth  ┃ shares? ┃
            # ┃ 1.0.8      ┃ no             ┃ YES     ┃
            # ┃ 1.0.8      ┃ yes            ┃ NO      ┃ 
            # ┃ 1.0.11-rc2 ┃ no             ┃ NO      ┃
            # ┃ 1.0.11-rc2 ┃ yes            ┃ NO      ┃
            # 
            # The Kryptex PRL pool's Stratum V1 named-params authorize ({user,pass})
            # works natively with peakminer 1.0.8. Setting --legacy-auth causes
            # the array-form authorize to be accepted at login but shares silently
            # never reach the share queue. v1.0.11-rc2 has a separate bug that
            # blocks shares entirely regardless of --legacy-auth.
            # 
            # PINNED to 1.0.8 until 1.0.11 is re-verified.
            # Do NOT enable legacyAuth or change pinnedVersion without re-testing.
            default = false;
            description = "Use Stratum V1 array-form authorize (--legacy-auth). KNOWN BROKEN on Kryptex PRL — keeps connection alive but blocks share submission.";
          };
          pinnedVersion = mkOption {
            type = types.str;
            default = "1.0.8";
            description = "PeakMiner version pin. 1.0.8 confirmed working; 1.0.11-rc2 never submits shares on Kryptex. Used for documentation reference — actual package selection is per-flake.";
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
    # peakminer 1.0.11-rc2 --help confirms pool URLs require a `stratum+tcp://` or `stratum+ssl://`
    # scheme prefix; bare host:port is rejected by the CLI parser. Enforce at eval time so a
    # typo is caught on `just check` instead of silently failing at miner startup.
    assertions = [
      {
        assertion = lib.all (i:
          lib.all (url: lib.hasPrefix "stratum+" url) i.pools
        ) cfg.instances;
        message = "services.peakminer: every instance pool URL must begin with `stratum+tcp://` or `stratum+ssl://` (peakminer 1.0.8 hard requirement; bare `host:port` is rejected).";
      }
    ];
    systemd.services = lib.listToAttrs (
      builtins.map (instance: let
        poolArgs = builtins.map (p: "--url ${p}") instance.pools;
        powerLimitArgs =
          if instance.powerLimit != null
          then "+/run/current-system/sw/bin/nvidia-smi -i ${toString instance.gpuId} -pl ${toString instance.powerLimit}"
          else "";
        # Power limit intentionally applies via nvidia-smi (ExecStartPre/Post) -- NOT --gpu-power.
        # peakminer NVML OC silently fails on NixOS because libnvidia-ml.so.1 dlopen breaks under
        # pure glibc + LD_LIBRARY_PATH from /run/opengl-driver. nvidia-smi -pl works reliably.
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
      in {
        name = "peakminer-${instance.name}";
        value = {
          description = "PeakMiner - ${instance.name}";
          wantedBy = ["multi-user.target"];
          after = ["network-online.target"];
          wants = ["network-online.target"];

          serviceConfig = {
            Type = "simple";
            User = cfg.user;
            ExecStartPre = lib.mkIf (instance.powerLimit != null) (
              lib.mkBefore powerLimitArgs
            );
            # ExecStartPost re-applies the power limit AFTER peakminer starts,
            # because peakminer's NVML OC silently fails on NixOS and leaves
            # the GPU at its default power envelope. nvidia-smi -pl works reliably.
            ExecStartPost = lib.mkIf (instance.powerLimit != null) (
              "+/run/current-system/sw/bin/nvidia-smi -i ${toString instance.gpuId} -pl ${toString instance.powerLimit}"
            );
            ExecStart = pkgs.writeShellScript "peakminer-${instance.name}" ''
              export CUDA_DEVICE_ORDER=PCI_BUS_ID
              # PeakMiner needs NVML + CUDA runtime libraries from the driver
              export LD_LIBRARY_PATH=/run/opengl-driver/lib:''${LD_LIBRARY_PATH:-}
              exec ${pkgs.peakminer}/bin/peakminer \
                --coin pearl \
                ${lib.concatStringsSep " " poolArgs} \
                --user ${instance.wallet} \
                --devices ${instance.devices} \
                --api-port ${toString instance.apiPort} \
                ${lib.concatStringsSep " " tempArg} \
                ${lib.concatStringsSep " " fanArg} \
                ${lib.optionalString instance.legacyAuth "--legacy-auth"} \
                ${lib.concatStringsSep " " instance.extraArgs}
            '';
            Restart = "always";
            RestartSec = 10;
          };
        };
      }) cfg.instances
    );
  };
}

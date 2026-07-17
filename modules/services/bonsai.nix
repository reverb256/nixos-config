# Bonsai 27B llama-server deployments
#
# Self-hosted inference endpoints for The Echo Chamber game (see ~/Projects/Game).
#   - Zephyr RTX 3090 (GPU 1): Ternary-Bonsai-27B (Q2_0_g128, 6.7 GB) on port 1237
#   - Forge RTX 4060 (GPU 0): 1-bit Bonsai-27B (Q1_0, 3.6 GB) on port 8002
#   - Sentry RX 5600 XT: 1-bit Bonsai-27B via Vulkan on port 8003 (TODO: ROCm/Vulkan backend decision)
#
# The PrismML fork binary is REQUIRED for the ternary variant (ggml type 42, not in
# mainline llama.cpp). Build it with:
#   cd /tmp/prism-llama && NIXPKGS_ALLOW_UNFREE=1 nix build .#cuda --builders '' --max-jobs 2 --impure
# then point binaryStorePath at the resulting /nix/store/...-llama-cpp-cuda path.
# Models: /models/bonsai/{ternary-27b,1bit-27b} (downloaded, verified valid GGUF v3).
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.bonsai;

  # Wrap the externally-built PrismML fork binary into a package the module can consume.
  # The fork is NOT a flake input (it's built ad-hoc on zephyr against CUDA 13.1); we
  # reference its realized store path. Keep this path in sync after each rebuild.
  prismBinary = pkgs.runCommand "prism-llama-bonsai" { } ''
    mkdir -p $out/bin
    cp -rL ${cfg.binaryStorePath}/bin/llama-server $out/bin/llama-server
    # Copy companion libs alongside so the static binary finds its CUDA/ggml .so at runtime
    for lib in ${cfg.binaryStorePath}/lib/*.so*; do
      cp -rL "$lib" $out/bin/ 2>/dev/null || true
    done
  '';
in {
  options.services.bonsai = {
    enable = mkEnableOption "Bonsai 27B llama-server inference";

    # Realized store path of the PrismML fork build (e.g. /nix/store/xxx-llama-cpp-cuda).
    # Required because the ternary GGUF uses a custom ggml type only the fork understands.
    binaryStorePath = mkOption {
      type = types.str;
      description = "Store path of the built PrismML llama.cpp fork (nix build .#cuda output)";
      example = "/nix/store/00000000000000000000000000000000-llama-cpp-cuda";
    };

    package = mkOption {
      type = types.package;
      default = prismBinary;
      description = "PrismML llama.cpp package (llama-server binary). Defaults to binaryStorePath wrapper.";
    };

    ternaryModel = mkOption {
      type = types.path;
      default = "/models/bonsai/ternary-27b/Ternary-Bonsai-27B-Q2_0.gguf";
    };

    onebitModel = mkOption {
      type = types.path;
      default = "/models/bonsai/1bit-27b/Bonsai-27B-Q1_0.gguf";
    };

    dsparkModel = mkOption {
      type = types.nullOr types.path;
      default = "/models/bonsai/dspark/Ternary-Bonsai-27B-dspark-Q4_1.gguf";
    };

    mmproj = mkOption {
      type = types.nullOr types.path;
      default = "/models/bonsai/ternary-27b/Ternary-Bonsai-27B-mmproj-Q8_0.gguf";
    };
  };

  config = mkIf cfg.enable {
    # GPU-bound inference: cannot use DynamicUser (needs /dev/nvidia* + persistent
    # model files). Run as a dedicated system user, sandboxed otherwise.
    users.users.bonsai = {
      isSystemUser = true;
      group = "bonsai";
      description = "Bonsai 27B inference service";
    };
    users.groups.bonsai = {};

    systemd.services.bonsai-ternary-zephyr = {
      description = "Bonsai 27B Ternary — Zephyr RTX 3090 (port 1237)";
      after = ["network.target" "systemd-udev-settle.service"];
      wants = ["systemd-udev-settle.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        User = "bonsai";
        RuntimeDirectory = "bonsai-ternary";
        ExecStart = "${getExe cfg.package} -m ${cfg.ternaryModel} --host 0.0.0.0 --port 1237 -ngl 99 -fa on -c 0 --temp 0.7 --top-p 0.95 --top-k 20 --min-p 0 --jinja --alias ternary-bonsai-27b${lib.optionalString (cfg.mmproj != null) " --mmproj ${cfg.mmproj}"}";
        Restart = "on-failure";
        RestartSec = "10";
        StandardOutput = "journal";
        StandardError = "journal";
        MemoryMax = "20G"; # 6.7GB weights + KV cache headroom on the 24GB 3090
        LimitNOFILE = 65536;
        OOMScoreAdjust = 500;
        # GPU access + model read; no network bind privilege needed (listens on 0.0.0.0 ephemeral)
        AmbientCapabilities = [ "CAP_SYS_RAWIO" ];
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [ "/run/bonsai-ternary" ];
        ReadOnlyPaths = [ "${cfg.ternaryModel}" "${cfg.mmproj}" ];
      };

      environment = {
        CUDA_VISIBLE_DEVICES = "1"; # RTX 3090
        CUDA_CACHE_DISABLE = "1"; # avoid per-user cache writes under ProtectHome
      };
    };

    systemd.services.bonsai-1bit-forge = {
      description = "Bonsai 27B 1-bit — Forge RTX 4060 (port 8002)";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        User = "bonsai";
        RuntimeDirectory = "bonsai-1bit-forge";
        ExecStart = "${getExe cfg.package} -m ${cfg.onebitModel} --host 0.0.0.0 --port 8002 -ngl 99 -fa on -c 0 --temp 0.5 --top-p 0.85 --top-k 20 --min-p 0 --alias bonsai-27b-1bit";
        Restart = "on-failure";
        RestartSec = "10";
        StandardOutput = "journal";
        StandardError = "journal";
        MemoryMax = "6G"; # 3.6GB weights + KV on the 8GB 4060
        LimitNOFILE = 65536;
        OOMScoreAdjust = 500;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = [ "/run/bonsai-1bit-forge" ];
        ReadOnlyPaths = [ "${cfg.onebitModel}" ];
      };

      environment = {
        CUDA_VISIBLE_DEVICES = "0";
      };
    };
  };
}

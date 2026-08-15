# Bonsai 27B llama-server deployments
#
# Self-hosted inference across the homelab. Ternary (2-bit, 6.7 GB) runs on
# larger NVIDIA GPUs when not mining; 1-bit (3.5 GB) runs everywhere.
#
#   Host          GPU(s)                          Ternary port  1-bit port
#   ──────────────────────────────────────────────────────────────────────
#   Zephyr        RTX 3090 (GPU 1) + 3060 Ti (0)  8005          1236
#   Nexus         RTX 3060 Ti                     —             1235
#   Forge         RTX 4060 (GPU 0,1)               —             8002,8006
#   Sentry        AMD RX 5600 XT (Vulkan)         —             8003
#   krash3        CPU-only                        —             8004
#
# NVIDIA hosts use the PrismML llama.cpp fork (CUDA):
#   cd /tmp/prism-llama-fork
#   NIXPKGS_ALLOW_UNFREE=1 nix build .#cuda --builders '' --max-jobs 2 --impure
# AMD hosts (sentry) use MAINLINE llama.cpp with the Vulkan backend
# (pkgs.llama-cpp). 1-bit Q1_0 Bonsai runs on mainline Vulkan — no PrismML
# fork Vulkan build required. Weights default to /models/bonsai but the
# sentry host overrides onebitModel to /srv/models (sentry has no /models).
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.bonsai;
  host = config.networking.hostName;

  # Wrap the PrismML fork CUDA binary into a package.
  # 2026-07-29: Fail-fast on misconfiguration — throw if enable is true but no
  # binaryStorePath is set, rather than silently falling back to upstream.
  # 2026-08-13: GC hazard documented. binaryStorePath is interpolated as a
  # string, invisible to the store DB — nix-collect-garbage deleted the binary
  # on forge while the wrapper survived (status 127 crash loop). builtins.storePath
  # was tried as a fix but is BANNED in pure eval (colmena deploys pure). Durable
  # fix is the unified llama-cpp flake package (packages.llama-cpp-unified):
  # hosts must point binaryStorePath at a proper flake output so colmena copies
  # it and GC keeps it. Until migrated, restore a GC'd binary by copying it from
  # a host that still has it (nexus/zephyr).
  # Durable default: the unified PrismML fork package (CUDA+Vulkan, Q1_0/Q2_0
  # repack, DSpark, CPU-MoE) from the overlay/flake. It is a REAL derivation,
  # so colmena copies it to targets and GC keeps it — no string-path hazard.
  # Hosts may still pin a specific fork store path via binaryStorePath (e.g.
  # the old 560rfa8pm build) but should migrate to the unified package.
  # Always a wrapper script named llama-server-bonsai so getExe resolves the
  # server binary (the raw package's mainProgram is llama-cli, which takes no
  # --host/--port). The unified package is interpolated as "${...}" so Nix
  # records a REAL dependency: colmena copies it, GC keeps it.
  # Sentry (AMD-only) must use llama-cpp-unified-vulkan: the CUDA+Vulkan build
  # hard-links libcuda.so.1 (DT_NEEDED) and the loader dies before Vulkan
  # initializes on AMD-only hosts (verified 2026-08-13).
  effectiveLlama =
    if host == "sentry"
    then pkgs.llama-cpp-unified-vulkan
    else pkgs.llama-cpp-unified;
  prismBinary =
    if cfg.binaryStorePath != null
    then
      pkgs.writeShellScriptBin "llama-server-bonsai" ''
        export LD_LIBRARY_PATH="${cfg.binaryStorePath}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        exec ${cfg.binaryStorePath}/bin/llama-server "$@"
      ''
    else
      pkgs.writeShellScriptBin "llama-server-bonsai" ''
        export LD_LIBRARY_PATH="${effectiveLlama}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        exec ${effectiveLlama}/bin/llama-server "$@"
      '';

  # Optional PrismML fork Vulkan binary (NVIDIA/AMD fork build).
  prismVulkanBinary =
    if cfg.vulkanBinaryStorePath != null
    then
      pkgs.writeShellScriptBin "llama-server-bonsai-vulkan" ''
        export LD_LIBRARY_PATH="${cfg.vulkanBinaryStorePath}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        exec ${cfg.vulkanBinaryStorePath}/bin/llama-server "$@"
      ''
    else null;

  # Mainline llama.cpp (nixpkgs) with the Vulkan backend — for AMD/Radeon
  # hosts running 1-bit Q1_0 Bonsai. No fork build required.
  # CUDA support is DISABLED so the binary does not hard-link libcuda.so.1
  # (which is absent on AMD-only hosts and crashes the loader before Vulkan
  # can initialise). Vulkan backend stays enabled by default in nixpkgs.
  # VK_ICD_FILENAMES is forced to the mesa RADV ICD so llama.cpp's Vulkan
  # loader finds the GPU even when the system icd.d lacks the radeon symlink
  # (sentry's headless setup). LD_LIBRARY_PATH wires the llama.cpp libs.
  mainlineVulkanBinary =
    if cfg.vulkanMainlinePackage != null
    then
      pkgs.writeShellScriptBin "llama-server-bonsai-mainline-vulkan" ''
        export VK_ICD_FILENAMES="${pkgs.mesa}/share/vulkan/icd.d/radeon_icd.x86_64.json"
        export LD_LIBRARY_PATH="${cfg.vulkanMainlinePackage}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        exec ${cfg.vulkanMainlinePackage}/bin/llama-server "$@"
      ''
    else null;

  # Fork (PrismML) Vulkan binary — the unified fork's Vulkan-only variant for
  # AMD-only hosts (sentry). Same fork source as llama-cpp-unified (Q1_0/Q2_0
  # repack, CPU-MoE, DSpark) minus the CUDA backend, which hard-links
  # libcuda.so.1 (DT_NEEDED) and cannot load on AMD hosts. RADV ICD forced for
  # the same reason as mainlineVulkanBinary.
  forkVulkanBinary = pkgs.writeShellScriptBin "llama-server-bonsai-fork-vulkan" ''
    export VK_ICD_FILENAMES="${pkgs.mesa}/share/vulkan/icd.d/radeon_icd.x86_64.json"
    export LD_LIBRARY_PATH="${pkgs.llama-cpp-unified-vulkan}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    exec ${pkgs.llama-cpp-unified-vulkan}/bin/llama-server "$@"
  '';

  # turboQuant binary wrapper — wraps the retroheim turbo build.
  turboPackage =
    if cfg.turboBinaryStorePath != null
    then
      pkgs.writeShellScriptBin "llama-server-turbo-asym" ''
        exec ${cfg.turboBinaryStorePath}/llama-server-turbo "$@"
      ''
    else null;

  # Override for asymmetric KV services
  effectivePackage =
    if cfg.turboBinaryStorePath != null
    then turboPackage
    else cfg.package;

  # Shorthand: 1-bit Bonsai service (3.5 GB). Uses explicit context & q4_0 KV.
  # `model` and `memoryMax` are overridable per-host (sentry uses /srv/models
  # and a smaller ctx/ram cap than the 8-24 GB NVIDIA hosts). Also opens the
  # service port in the host firewall (cluster convention: mkOptionDefault).
  mk1bitService = {
    name,
    desc,
    port,
    gpu ? null,
    extraEnv ? {},
    binary ? prismBinary,
    # 2026-08-15: extra ordering deps. forge-vk1 starts AFTER vk0 so two 3.5GB
    # model loads never overlap on forge's 15GB box (earlyoom SIGTERM'd vk0 —
    # simultaneous load peaked at 2.1G each, system avail hit 0 MiB).
    afterUnits ? [],
    model ? cfg.onebitModel,
    contextSize ? "262144",
    cacheTypeK ? "turbo4",
    cacheTypeV ? "turbo4",
    # 2026-08-15: RDNA1 Vulkan MUST run -fa off (3x faster decode, sentry
    # playbook). NVIDIA hosts keep the default "on".
    fa ? "on",
    # 2026-08-15: gpuLabel feeds the workload registry (kind="direct") so the
    # fuzzel menu shows this unit with live state. null = no registry entry.
    gpuLabel ? null,
    memoryMax ? "6G",
    parallel ? 1,
    specType ? null,
    specDraftNMax ? null,
    draftModel ? null,
  }: {
    systemd.services."bonsai-1bit-${name}" = {
      description = desc;
      after = ["network.target"] ++ afterUnits;
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        User = "bonsai";
        RuntimeDirectory = "bonsai-1bit-${name}";
        ExecStart =
          "${getExe binary} -m ${model} --host 0.0.0.0 --port ${toString port} -ngl 99 -fa ${fa} -c ${contextSize} --cache-type-k ${cacheTypeK} --cache-type-v ${cacheTypeV} --fit off --temp 0.7 --top-p 0.95 --top-k 20 --min-p 0 --jinja --parallel ${toString parallel} --alias bonsai-27b-1bit-${name}"
          + optionalString (specType != null) " --spec-type ${specType}"
          + optionalString (specDraftNMax != null) " --spec-draft-n-max ${toString specDraftNMax}"
          + optionalString (draftModel != null) " -md ${draftModel}";
        Restart = "on-failure";
        RestartSec = "10";
        StandardOutput = "journal";
        StandardError = "journal";
        MemoryMax = memoryMax;
        LimitNOFILE = 65536;
        OOMScoreAdjust = 500;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = ["/run/bonsai-1bit-${name}"];
        ReadOnlyPaths = [model] ++ optionals (draftModel != null) [draftModel];
      };
      environment =
        optionalAttrs (gpu != null) {CUDA_VISIBLE_DEVICES = gpu;}
        // {
          # UMA OFF on every host: =1 would spill GPU memory into system RAM
          # and earlyoom-kill llama-server (observed on zephyr 2026-08-12 at
          # 51 MiB free). Explicit per-process control; never inherit session.
          GGML_CUDA_ENABLE_UNIFIED_MEMORY = "0";
        }
        // extraEnv;
    };
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [port];
    # Workload registry: every direct unit is a kind="direct" workload. The
    # menu reads /etc/cluster/workloads.json at runtime — no menu edit needed
    # when units are added/removed here (gpu-workload-registry module).
    services.gpu-workload-registry.workloads.${host} = optionals (gpuLabel != null) [{
      id = "bonsai-1bit-${name}";
      name = desc;
      gpuLabel = gpuLabel;
      kind = "direct";
      port = port;
      swapId = null;
      swapPort = null;
      alwaysOn = true;
    }];
  };

  # Shorthand: Ternary Bonsai service (6.7 GB).
  mkTernaryService = {
    name,
    desc,
    port,
    gpu,
    memoryMax ? "20G",
    extraFlags ? "",
    extraEnv ? {},
  }: {
    systemd.services."bonsai-ternary-${name}" = {
      description = desc;
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "simple";
        User = "bonsai";
        RuntimeDirectory = "bonsai-ternary-${name}";
        ExecStart =
          "${getExe prismBinary} -m ${cfg.ternaryModel}"
          + (
            if cfg.dsparkModel != null
            then " --spec-type draft-dspark --model-draft ${cfg.dsparkModel} --spec-draft-n-max 4"
            else ""
          )
          + (
            if cfg.mmproj != null
            then " --mmproj ${cfg.mmproj}"
            else ""
          )
          + " --host 0.0.0.0 --port ${toString port} -ngl 99 -fa on -c 262144 --cache-type-k q8_0 --cache-type-v q8_0 --fit off --temp 0.7 --top-p 0.95 --top-k 20 --min-p 0 --jinja --parallel 1 --alias ternary-bonsai-27b-${name}";
        Restart = "on-failure";
        RestartSec = "10";
        StandardOutput = "journal";
        StandardError = "journal";
        MemoryMax = memoryMax;
        LimitNOFILE = 65536;
        OOMScoreAdjust = 500;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadWritePaths = ["/run/bonsai-ternary-${name}"];
        ReadOnlyPaths = [cfg.ternaryModel] ++ optional (cfg.mmproj != null) cfg.mmproj ++ optional (cfg.dsparkModel != null) cfg.dsparkModel;
      };
      environment =
        {
          CUDA_VISIBLE_DEVICES = gpu;
          CUDA_CACHE_DISABLE = "1";
          # UMA OFF on every host (see mk1bitService note; same earlyoom risk).
          GGML_CUDA_ENABLE_UNIFIED_MEMORY = "0";
        }
        // extraEnv;
    };
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [port];
  };

  # ── All services, each gated by hostname ──

  # Ternary on zephyr 3090 (CUDA0 = 24 GB) — full capabilities including vision + DSpark
  # NOTE: llama.cpp enumerates CUDA0 = RTX 3090, CUDA1 = RTX 3060 Ti — the
  # REVERSE of nvidia-smi (GPU0 = 3060 Ti, GPU1 = 3090). GPU pinning uses
  # CUDA_VISIBLE_DEVICES, so ternary (24 GB card) = "0", 1-bit (8 GB) = "1".
  # DISABLED on zephyr: home-manager owns zephyr bonsai (user units). The
  # system unit uses User=bonsai, which does not exist on zephyr -> status=217
  # crash-loop that fails the colmena post-activation health check on EVERY
  # zephyr deploy (2026-08-13). Re-enable only if zephyr bonsai moves back to
  # systemd-system management AND the bonsai user is created.
  ternaryZephyr = mkIf (host == "zephyr" && false) (mkTernaryService {
    name = "zephyr";
    desc = "Bonsai 27B Ternary — Zephyr RTX 3090 (port 8005) q8_0 KV + DSpark";
    port = 8005;
    gpu = "0";
    memoryMax = "20G";
    extraEnv = {
      GGML_CUDA_GRAPH_OPT = "1";
      LLAMA_ATTN_ROT_DISABLE = "1";
      CUDA_SCALE_LAUNCH_QUEUES = "4";
      LD_LIBRARY_PATH = "/usr/local/lib/bonsai-turbo:/run/opengl-driver/lib";
    };
  });

  # 1-bit on zephyr 3060 Ti (CUDA1 = 8 GB) — explicit 128K + q4_0 KV
  # DISABLED on zephyr: HM owns zephyr bonsai (see ternaryZephyr note).
  bit1Zephyr = mkIf (host == "zephyr" && false) (mk1bitService {
    name = "zephyr";
    desc = "Bonsai 27B 1-bit — Zephyr RTX 3060 Ti (port 1236) q4_0 KV 128K";
    port = 1236;
    gpu = "1";
  });

  # 1-bit on nexus 3060 Ti (8 GB)
  # REMOVED 2026-08-14: llama-swap on nexus owns Bonsai now (q4_0 KV @ 256K,
  # /etc/llama-swap/nexus.yaml catalog, swap proxy :21759, model :21760).
  # The direct unit crash-looped (MemoryMax=6G cgroup OOM at 262144 ctx) and
  # fought the swap for VRAM. The deployed unit was masked imperatively; this
  # definition is deleted so no future nixos-rebuild regenerates it.

  # NOTE: ternary on nexus was REMOVED (2026-08-12). The 3060 Ti is an 8 GB
  # card shared with ComfyUI + peakminer + gamescope (~3 GB busy); ternary
  # (6.7 GB) + DSpark drafter never fit -> cudaMalloc OOM -> 119 restarts.
  # Nothing consumed port 1238. If GPU-idle scheduling is ever wanted, add a
  # proper gate (stop 1-bit + require <1 GB GPU busy) — do NOT re-enable
  # unconditionally.

  # 1-bit on forge 4060 GPU 0 (8 GB)
  # 2026-08-15: gated behind enableForge0 — the 4060s went back to 100% mining
  # when the 5700 XTs took over inference (bit1ForgeVk0/1). A CUDA bonsai on
  # a mining 4060 is a compute-sharing squat; the AMD pair is dedicated.
  bit1Forge0 = mkIf (host == "forge" && cfg.enableForge0) (mk1bitService {
    name = "forge-0";
    desc = "Bonsai 27B 1-bit — Forge RTX 4060 GPU 0 (port 8002) turbo4 KV 256k";
    port = 8002;
    gpu = "0";
    contextSize = "262144";
  });

  # 1-bit on forge 4060 GPU 1 (8 GB)
  bit1Forge1 = mkIf (host == "forge" && cfg.enableForge1) (mk1bitService {
    name = "forge-1";
    desc = "Bonsai 27B 1-bit — Forge RTX 4060 GPU 1 (port 8006) turbo4 KV 256k";
    port = 8006;
    gpu = "1";
    contextSize = "262144";
  });

  # 1-bit on forge AMD RX 5700 XT pair via Vulkan — DEDICATED inference cards.
  # 2026-08-15 decision (bench-backed): the two 5700 XTs (Vulkan1/Vulkan2)
  # measure 89 t/s prefill / 13.7 t/s decode on Bonsai 27B Q1_0 — faster than
  # the 4060 CUDA path. The 4060s go back to 100% mining; the AMD pair serves
  # bonsai always-on. RDNA1 playbook env (sentry 5600 XT, same gfx1010 family):
  #   GGML_VK_MAX_NODES_PER_SUBMIT=1 (DeviceLost fix, upstream #21724/#24872)
  #   RADV_PERFTEST=nogttspill (GTT-spill collapse, Mesa 25.2+)
  #   TURBO_AUTO_ASYMMETRIC=0 (auto-asymmetric upgraded K to q8_0 -> 2x cost)
  #   -fa off (Vulkan FA on RDNA1 = 3x slower decode)
  #   VK_ICD_FILENAMES=radeon (device index = AMD-only; 0 and 1 are the 5700 XTs)
  #   2x 128K slots (parallel 2) like sentry — 256K/slot needs 4.8G KV, OOMs.
  bit1ForgeVk0 = mkIf (host == "forge" && cfg.enableForgeVk) (mk1bitService {
    name = "forge-vk0";
    desc = "Bonsai 27B 1-bit — Forge AMD RX 5700 XT-0 via Vulkan (port 8007) turbo4 KV 128K";
    port = 8007;
    binary = prismBinary;
    gpuLabel = "5700 XT-0";
    fa = "off";
    contextSize = "131072";
    cacheTypeK = "turbo4";
    cacheTypeV = "turbo4";
    parallel = 2;
    # 15GB box: 2 instances -> 12G total cgroup cap. 8G each was > physical
    # and earlyoom killed vk0 during simultaneous load.
    memoryMax = "6G";
    extraEnv = {
      GGML_VULKAN_DEVICE = "0";
      VK_ICD_FILENAMES = "${pkgs.mesa}/share/vulkan/icd.d/radeon_icd.x86_64.json";
      GGML_VK_MAX_NODES_PER_SUBMIT = "1";
      RADV_PERFTEST = "nogttspill";
      TURBO_AUTO_ASYMMETRIC = "0";
    };
  });

  # 2026-08-15 (3): DISABLED by default — forge has 15GB system RAM. Two
  # resident 3.5GB instances + k3s + miners + alloy = swap write errors on
  # /dev/zram0 -> kernel wedged -> auto-reboot (happened 3x in 20 min). The
  # 5700 XT pair measures IDENTICAL single-card speed (13.7 t/s decode), so
  # one instance (vk0) loses nothing. Re-enable only with a memory budget
  # (e.g. --no-mmap or a bigger host).
  bit1ForgeVk1 = mkIf (host == "forge" && cfg.enableForgeVk1) (mk1bitService {
    name = "forge-vk1";
    desc = "Bonsai 27B 1-bit — Forge AMD RX 5700 XT-1 via Vulkan (port 8008) turbo4 KV 128K";
    port = 8008;
    binary = prismBinary;
    gpuLabel = "5700 XT-1";
    fa = "off";
    contextSize = "131072";
    cacheTypeK = "turbo4";
    cacheTypeV = "turbo4";
    parallel = 2;
    # Stagger after vk0: model loads (2.1G peak each) must not overlap on 15GB.
    afterUnits = ["bonsai-1bit-forge-vk0.service"];
    memoryMax = "6G";
    extraEnv = {
      GGML_VULKAN_DEVICE = "1";
      VK_ICD_FILENAMES = "${pkgs.mesa}/share/vulkan/icd.d/radeon_icd.x86_64.json";
      GGML_VK_MAX_NODES_PER_SUBMIT = "1";
      RADV_PERFTEST = "nogttspill";
      TURBO_AUTO_ASYMMETRIC = "0";
    };
  });

  # NOTE: ternary on forge was REMOVED (2026-08-12) — same root cause as nexus:
  # both 4060s mine 24/7 at 100% util on 8 GB cards; ternary (6.7 GB) +
  # drafter never fit -> 379 restarts. Ternary is zephyr-only (24 GB 3090).
  # Do NOT re-enable without a real idle gate.

  # 1-bit on sentry AMD via MAINLINE llama.cpp Vulkan (no fork build).
  # 5600 XT has 6 GB VRAM — Bonsai is hybrid-attention (only 16/64 layers
  # cache), so KV is small. Testing how far -c can go on 6 GB (q4_0 KV).
  # VK_ICD_FILENAMES forces RADV discovery. CUDA disabled (no libcuda on AMD).
  # NO DSpark drafter here: mainline llama.cpp cannot load the 'dspark' draft
  # architecture (unknown model architecture: 'dspark' -> exit 1 -> crash loop),
  # and the drafter never fit 6 GB VRAM anyway (3060 Ti history: OOM -> 119/379
  # restarts). Plain 1-bit Vulkan is the stable config.
  bit1Sentry = mkIf (host == "sentry") (mk1bitService {
    name = "sentry";
    desc = "Bonsai 27B 1-bit — Sentry AMD RX 5600 XT via Vulkan (port 8003)";
    port = 8003;
    binary = forkVulkanBinary;
    extraEnv = {
      GGML_VULKAN_DEVICE = "0";
      VK_ICD_FILENAMES = "${pkgs.mesa}/share/vulkan/icd.d/radeon_icd.x86_64.json";
      # 2026-08-14: force turbo4 K — auto-asymmetric upgraded K to q8_0
      # (GQA 6:1) which doubled K-cache cost; on 6GB VRAM prefill crawled
      # at 23 t/s and a trivial prompt hung 100+s. turbo4 K keeps 256K
      # usable on the 5600 XT (forge can afford q8_0 K on 8GB, sentry can't).
      TURBO_AUTO_ASYMMETRIC = "0";
      # 2026-08-14 (2): DeviceLost crash-loop fix (upstream llama.cpp #21724
      # + PR #24872). AMD RADV resets the compute ring when one vkQueueSubmit
      # batch (default 100 nodes) exceeds amdgpu.lockup_timeout (2000ms).
      # Sentry was crash-looping with vk::Queue::submit: ErrorDeviceLost on
      # long prefills + request cancellation. Max nodes per submit = 1 splits
      # submissions so none exceeds the kernel watchdog; upstream measured
      # no perf regression.
      GGML_VK_MAX_NODES_PER_SUBMIT = "1";
      # 2026-08-14 (3): RADV GTT-spill fix (upstream llama.cpp #24066 / #13765,
      # Mesa #13282). RADV misallocates buffers to GTT (system RAM) even when
      # VRAM is free, collapsing throughput 3-6x. RADV_PERFTEST=nogttspill
      # (Mesa 25.2+) forces VRAM-first allocation and restored full speed in
      # upstream bisects (pp 207->2807, tg 51->136 on RX 7900 XTX). Mesa on
      # sentry is 26.1.5, flag supported.
      RADV_PERFTEST = "nogttspill";
    };
    # 2026-08-14: 8K was pinned for 6GB VRAM safety, but agents send 37-48K
    # token prompts (rejected daily) and Hermes requires 64K minimum. The
    # turboquant fork supports turbo4 KV (~4-bit, kv-offload default on).
    # 2026-08-14 (2): --parallel 2 -c 131072 — two 128K slots = same total
    # KV as one 256K slot (2.4G), no new VRAM risk, but concurrent requests
    # (gateway + cron) stop queueing behind each other. 128K/slot still 2x
    # the Hermes 64K minimum. 256K/slot at parallel 2 would need 4.8G KV
    # and OOM the 6GB card.
    contextSize = "131072";
    cacheTypeK = "turbo4";
    cacheTypeV = "turbo4";
    parallel = 2;
    memoryMax = "6G";
  });

  # Gemma 4 E2B on sentry — served via llama-swap (see
  # llama-swap-cluster.nix sentry.yaml, swapId gemma-e2b, proxy :21764).
  # 2026-08-14 history: the direct unit was the first E2B deployment (port
  # 8003, FA off, f16 V + q8_0 K, 128K). It measured 84-94 t/s decode.
  # REMOVED 2026-08-14 (2): all models must live in the llama-swap catalog
  # (harmonization) — a direct unit outside the swap cannot be unloaded by
  # the swap, causing VRAM contention when the catalog loads. The gateway
  # now points at the sentry swap proxy 127.0.0.1:21764. Do NOT re-add a
  # direct unit here.

  # 1-bit on krash3 CPU-only (no GPU available)
  bit1Krash3 = mkIf (host == "krash3") (mk1bitService {
    name = "krash3";
    desc = "Bonsai 27B 1-bit — krash3 CPU-only (port 8004)";
    port = 8004;
    extraEnv = {};
    contextSize = "131072";
    cacheTypeK = "q4_0";
    cacheTypeV = "q4_0";
  });
in {
  options.services.bonsai = {
    enable = mkEnableOption "Bonsai 27B llama-server inference";

    binaryStorePath = mkOption {
      # types.path: an in-store string coerces to a path VALUE, so the wrapper
      # interpolates with string context -> Nix records a real dependency and
      # GC keeps the fork alive. Pure-eval-safe (builtins.storePath is not).
      type = types.nullOr types.path;
      default = null;
      description = ''
        Store path of the built PrismML llama.cpp fork (nix build .#cuda output). NVIDIA hosts.
        The path is wrapped with builtins.storePath so Nix records a real dependency: the
        fork cannot be garbage-collected while this config references it, and eval fails
        loudly if the path is missing on the builder (nexus). Copy the fork closure to the
        builder first: nix-copy-closure --to nexus <store-path>.
      '';
      example = "/nix/store/00000000000000000000000000000000-llama-cpp-cuda";
    };

    vulkanBinaryStorePath = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Store path of the PrismML fork built with Vulkan (AMD/Radeon hosts). Optional.";
      example = "/nix/store/xxx-llama-cpp-vulkan-0.0.0";
    };

    vulkanMainlinePackage = mkOption {
      type = types.nullOr types.package;
      default = pkgs.llama-cpp.override {
        cudaSupport = false;
        vulkanSupport = true;
      };
      description = "Mainline llama.cpp package with Vulkan backend and CUDA disabled (AMD/Radeon 1-bit Q1_0). No fork needed.";
      example = "pkgs.llama-cpp.override { cudaSupport = false; vulkanSupport = true; }";
    };

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = ''
        llama.cpp package (e.g. the flake's llama-cpp-unified output: PrismML
        Bonsai + TurboQuant KV + CUDA + Vulkan). Used by prismBinary when
        binaryStorePath is null. The wrapper (not getExe) resolves llama-server.
      '';
      example = lib.literalExpression ''pkgs.llama-cpp-unified'';
    };

    ternaryModel = mkOption {
      type = types.str;
      default = "/models/bonsai/ternary-27b/Ternary-Bonsai-27B-Q2_0.gguf";
    };

    onebitModel = mkOption {
      type = types.str;
      default = "/models/bonsai/1bit-27b/Bonsai-27B-Q1_0.gguf";
    };

    dsparkModel = mkOption {
      type = types.nullOr types.str;
      default = "/models/bonsai/dspark/Ternary-Bonsai-27B-dspark-Q4_1.gguf";
    };

    mmproj = mkOption {
      type = types.nullOr types.str;
      default = "/models/bonsai/ternary-27b/Ternary-Bonsai-27B-mmproj-Q8_0.gguf";
    };

    turboBinaryStorePath = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to turboQuant llama-server-turbo binary (retroheim fork)";
      example = "/home/j_kro/.local/share/bonsai/bin/llama-server-turbo";
    };

    enableForge1 = mkOption {
      type = types.bool;
      default = true;
      description = "Run the second forge bonsai service (GPU 1). Disable when the GPU 1 miner holds most VRAM — the 3.5GB 1-bit model SIGSEGVs on allocation (libnvidia-eglcore) with <1GB free.";
    };

    enableForge0 = mkOption {
      type = types.bool;
      default = true;
      description = "Run the first forge bonsai service (GPU 0, CUDA on 4060-0). Set false when the 5700 XTs serve inference (AMD pair is dedicated; the 4060s mine 100%).";
    };

    enableForgeVk = mkOption {
      type = types.bool;
      default = false;
      description = "Run the forge AMD RX 5700 XT Vulkan bonsai pair (ports 8007/8008). The AMD cards are dedicated inference; 4060s stay 100% on mining.";
    };

    enableForgeVk1 = mkOption {
      type = types.bool;
      default = false;
      description = "Run the SECOND forge AMD instance (5700 XT-1, port 8008). Default off: 15GB RAM cannot hold two resident 3.5GB instances with the mining stack (swap write errors -> reboot). Enable only on a bigger host or with --no-mmap.";
    };
  };

  config = mkMerge [
    (mkIf cfg.enable {
      users.users.bonsai = {
        isSystemUser = true;
        group = "bonsai";
        description = "Bonsai 27B inference service";
      };
      users.groups.bonsai = {};
    })
    ternaryZephyr
    bit1Zephyr
    bit1Forge0
    bit1Forge1
    bit1ForgeVk0
    bit1ForgeVk1
    # 2026-08-14: sentry serves Gemma 4 E2B via llama-swap (see
    # llama-swap-cluster.nix sentry.yaml, swapId gemma-e2b, proxy :21764).
    # The old bit1Sentry unit definition is kept above (documented history)
    # but is NOT enabled — do not re-add it without re-checking VRAM.
    bit1Krash3
  ];
}

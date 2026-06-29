{
  config,
  lib,
  pkgs,
  inputs,
  ...

}: {
  environment.sessionVariables.TZ = "America/Winnipeg";

  imports = [
    inputs.disko.nixosModules.disko
    ./monitoring.nix
    ./firewall.nix
    ./hardware.nix
    ./desktop.nix
    ./services.nix
    ./disko.nix
    ./preservation.nix

    ../../modules/default.nix
    ../../modules/hardware/rgb-control.nix
    ../../modules/services/podman-support.nix
    ../../modules/services/k3s-cluster.nix
    ../../modules/services/keepalived-vip.nix
    ../../modules/services/sshfs-projects-mount.nix
  ];

    # Host-specific CPU/GPU optimization for llama.cpp (Zen1 + Ada: RTX 4060)
  nixpkgs.config = {
    allowUnfree = true;
    packageOverrides = pkgs: {
      llama-cpp-turboquant = pkgs.llama-cpp-turboquant.overrideAttrs (old: {
        CXXFLAGS = (old.CXXFLAGS or "") + " -march=x86-64-v3";
      });
      llama-cpp = pkgs.llama-cpp.override {
        cudaSupport = true;
      };
      llama-cpp-vulkan = pkgs.llama-cpp-vulkan.overrideAttrs (old: {
        CXXFLAGS = (old.CXXFLAGS or "") + " -march=x86-64-v3";
      });
    };
  };
  stylix = {
    base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-medium.yaml";
    image = ../../modules/desktop/wallpapers/gruvbox-dark-bg.png;
  };

  clusterNetworking = {
    enable = true;
    hostName = "forge";
    ipAddress = config.networking.cluster.hosts.forge.ip;
    interfaceName = lib.mkForce "eno1";
    wireless.enable = false;
    unbound.enable = true;
    unbound.listenAddress = config.networking.cluster.hosts.forge.ip;
  };

  # Block Hoyoverse telemetry domains (Genshin Impact, Honkai Star Rail, Zenless Zone Zero)
  networking.hoyoverse-telemetry-block.enable = true;

  networking.interfaces.eno1.ipv6.addresses = [
    {
      address = "fd00::130";
      prefixLength = 64;
    }
  ];

  boot.kernel.sysctl."net.ipv6.conf.all.disable_ipv6" = lib.mkForce 0;
  boot.kernel.sysctl."net.ipv6.conf.default.disable_ipv6" = lib.mkForce 0;
  boot.kernel.sysctl."net.ipv6.conf.eno1.disable_ipv6" = lib.mkForce 0;

  systemd.timers.flake-lock-sync.enable = true;
  services.flake-lock-sync.enable = true;

  kernel-hardening.zswap.maxPoolPercent = 20;

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;
    priority = 999;
  };

  services.earlyoom = {
    enable = true;
    freeSwapThreshold = 10;
    enableNotifications = true;
  };

  boot.kernel.sysctl."vm.min_free_kbytes" = lib.mkForce 524288;

  profiles.node.forge-mining.enable = true;
  services.ai-inference.backend.type = "llama-cpp";

  boot.kernelPackages =
    inputs.nix-cachyos-kernel.legacyPackages.x86_64-linux.linuxPackages-cachyos-latest-x86_64-v3;

  services.sshfs-projects-mount.enable = true;

  services.nfs-cluster-mounts = {
    enable = true;
    mountHermes = false;
    mountPi = false;
  };

  # Override noexec on /var for k3s re-exec
  fileSystems."/var/lib/rancher/k3s" = {
    device = "/var/lib/rancher/k3s";
    fsType = "none";
    options = ["bind" "rw" "nosuid"];
  };

  system.stateVersion = "26.05";
  services.unbound-common.enable = true;

  # STORAGE — Managed by disko.nix
  # System SSD: TEAM T253X2256G 256GB (sdb) — @root, @persistent, @nix
  # Storage HDD: ADATA SU635 240GB (sda) — @home, @var, @games

  nix.settings.auto-optimise-store = true;
  boot.resumeDevice = "/dev/disk/by-id/ata-TEAM_T253X2256G_TM701907310240040386-part2";
  disabledModules = [ "services/kmscon" "system/home-manager.nix" ];

  environment.systemPackages = [ pkgs.llama-cpp ];

  # ── Local LLM Inference — Declarative Services ────────────
  # 5700 XT #1 (Vulkan1) — Gemma-4-E4B-it (128K context)
  services.llamafile = {
    enable = true;
    modelPath = "/home/j_kro/models/gemma-4-E4B-it-Q4_K_M.gguf";
    modelName = "gemma-4-E4B-it-Q4_K_M";
    host = "0.0.0.0";
    port = 8002;
    ctxSize = 131072;
    gpuLayers = 99;
    vulkanDevice = "Vulkan1";
    parallelDecoding = 1;
    enableThinking = false;
    chatTemplate = "<start_of_turn>user\n{{prompt}}<end_of_turn>\n<start_of_turn>model\n";
  };

  # 5700 XT #2 (Vulkan2) — Qwen3.5-4B-Uncensored (256K context)
  systemd.services.llamafile-qwen-uncensored = {
    description = "Llama.cpp Qwen3.5-4B-Uncensored (Vulkan2)";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "simple";
      User = "j_kro";
      Group = "users";
      WorkingDirectory = "/home/j_kro";
      ExecStart = ''
        ${pkgs.llama-cpp-vulkan}/bin/llama-server \
          --model /home/j_kro/models/Qwen3.5-4B-Uncensored-Q4_K_M.gguf \
          --host 0.0.0.0 --port 8003 \
          -ngl 99 -c 262144 -t 8 \
          --batch-size 64 --ubatch-size 16 \
          --flash-attn on --parallel 2 \
          --device Vulkan2 \
          --chat-template '<|im_start|>system\n{{system_prompt}}<|im_end|>\n<|im_start|>user\n{{prompt}}<|im_end|>\n<|im_start|>assistant\n' \
          --temp 0.7 --top-k 40 --top-p 0.9 --min-p 0.05 \
          --metrics
      '';
      NoNewPrivileges = true;
      PrivateTmp = true;
      LimitNOFILE = 65536;
      Restart = "on-failure";
      RestartSec = "10s";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # Intel iGPU (Vulkan3) — Qwen3.5-2B (256K context, tiny model)
  systemd.services.llamafile-qwen-tiny = {
    description = "Llama.cpp Qwen3.5-2B (Vulkan3, Intel)";
    after = ["network.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "simple";
      User = "j_kro";
      Group = "users";
      WorkingDirectory = "/home/j_kro";
      ExecStart = ''
        ${pkgs.llama-cpp-vulkan}/bin/llama-server \
          --model /home/j_kro/models/Qwen3.5-2B-Instruct-Q4_K_M.gguf \
          --host 0.0.0.0 --port 8004 \
          -ngl 99 -c 262144 -t 4 \
          --batch-size 32 --ubatch-size 8 \
          --flash-attn on --parallel 1 \
          --device Vulkan3 \
          --chat-template '<|im_start|>system\n{{system_prompt}}<|im_end|>\n<|im_start|>user\n{{prompt}}<|im_end|>\n<|im_start|>assistant\n' \
          --temp 0.7 --top-k 40 --top-p 0.9 --min-p 0.05 \
          --metrics
      '';
      NoNewPrivileges = true;
      PrivateTmp = true;
      LimitNOFILE = 65536;
      Restart = "on-failure";
      RestartSec = "10s";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  networking.firewall.allowedTCPPorts = [ 8002 8003 8004 ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
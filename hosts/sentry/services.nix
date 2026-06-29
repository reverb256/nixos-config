{
  config,
  lib,
  pkgs,
  inputs, ...
}: let
  cluster = config.networking.cluster;
  # Vulkan-only llama-cpp for AMD RX 5600 XT (no CUDA)
  llama-cpp-vk = pkgs.llama-cpp.override {
    cudaSupport = false;
    vulkanSupport = true;
  };
in {
  time.timeZone = lib.mkForce "America/Winnipeg";
  services = {
    hermes-cli = {
      enable = true;
      apiKeyFile = "/run/secrets/zai-api-key";
      nvidiaApiKeyFile = "/run/secrets/nvidia-api-key";
      casdoorJwtFile = "/run/secrets/casdoor-hermes-jwt";
      opencodeGoApiKeyFile = "/run/secrets/opencode-go-api-key";
      opencodeZenApiKeyFile = "/run/secrets/opencode-api-key";
    };
    hermes-agent = {
      addToSystemPackages = true;
      settings = {
        model.default = "glm-4.7";
        model.provider = "zai";
        providers.zai = {
          base_url = "https://api.z.ai/api/coding/paas/v4";
          api_key_env = "ZAI_API_KEY";
          discover_models = true;
        };
        providers.nvidia = {
          base_url = "https://integrate.api.nvidia.com/v1";
          api_key_env = "NVIDIA_API_KEY";
          discover_models = true;
        };
      };
    environmentFiles = [ "/run/secrets/hermes-env" ];
    };
    k3s-cluster = {
      enable = true;
      role = "server";
      nodeName = "sentry";
      serverAddr = "https://${cluster.kubernetes.vip}:${toString cluster.kubernetes.apiPort}";
      tokenFile = "/run/secrets/k3s-cluster-token";
      nodeIP = cluster.hosts.sentry.ip;
    };

    keepalived-vip = {
      enable = true;
      vip = cluster.kubernetes.vip;
      interface = "eth0";
      priority = 90; # BACKUP — failover node only
    };

    gaming-detection.enable = false;
    gpu-profile-manager.enable = false;
    mining-coordinator.enable = false;

    nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedGzipSettings = true;
      virtualHosts."_" = {
        default = true;
        locations."= /".return = "200 'OK'";
        locations."= /".extraConfig = ''
          add_header Content-Type text/plain;
        '';
      };
    };

    spotify-spotx.enable = lib.mkDefault true;

    tailscale.enable = true;

    nixos-share = {
      enable = false;
      client.enable = true;
    };

    nfs-client = {
      enable = false;
      mountShared = true;
      mountHome = false;
      mountMedia = false;
    };

    # Secondary NFS data server for failover (hermes + pi state)
    nfs-data-server = {
      enable = true;
      exports = ''
        /data/hermes 10.1.1.0/24(rw,sync,no_subtree_check,root_squash,anonuid=1000,anongid=100,fsid=105)

        /data/pi 10.1.1.0/24(rw,sync,no_subtree_check,root_squash,anonuid=1000,anongid=100,fsid=106)
      '';
    };
    nfs-state-sync = {
      enable = true;
      sourceHost = "nexus";
    };

    syncthing-cluster = {
      enable = true;
    };

    sops-secrets-registry = {
      enable = true;
      kubernetes = true;
      aiServices = true;
      ci = true;
    };

    # Sync sops secrets to K8s
    k8s-secrets-sync.enable = true;
  };

  services.cluster-mesh.enable = true; # SSH service account for inter-node mesh
  # Create directories for hermes/pi bind mounts on Sentry
  systemd.tmpfiles.rules = [
    "d /data/hermes 0775 j_kro j_kro -"
    "d /data/pi 0775 j_kro j_kro -"
  ];

  # Cluster DNS configuration
  networking.cluster.dns.enable = true;

  # No X11 — pure Wayland only

  systemd.services.ai-inference-monitor = {
    wantedBy = lib.mkForce [];
    enable = false;
  };

  systemd.services.tailscaled.environment = {
    TS_ADVERTISE_ROUTES = "10.1.1.0/24";
    TS_ROUTES = "";
    TS_SSH = "true";
  };

  # Initrd SSH recovery + BTRFS snapshots
  services.cluster-ca = {
    enable = true;
    generateLeaf = false;
  };

  services.initrd-ssh-recovery = {
    enable = true;
    interface = "eth0";
    networkDriver = "r8169";
    port = 2222;
  };
  services.recovery-specialisation.enable = true;
  services.btrfs-boot-snapshot.enable = lib.mkForce false;

  services.cachix-auth.enable = true;
  services.ai-coding-tools = {
    enable = true;
    user = "j_kro";
    zaiApiKeyFile = "/run/secrets/zai-api-key";
    context7ApiKeyFile = "/run/secrets/context7-api-key";
    nvidiaNimApiKeyFile = "/run/secrets/nvidia-api-key";
    opencodeGoApiKeyFile = "/run/secrets/opencode-go-api-key";
    tools = {
      claude = {enable = true;};
      opencode = {enable = true;};
      droid = {enable = true;};
      crush = {enable = true;};
      pi = {enable = true;};
      omp = {enable = true;};
    };
    enableShellEnv = true;
  };

 # GitHub Actions self-hosted runner for CI/CD
 # Disabled: Invalid PAT token causing setup failures
 # services.ci-runner = {
 #   enable = true;
 #   repo = "reverb256/nixos-config";
 #   tokenFile = null;
 #   patFile = "/run/secrets/github-runner-pat";
 #   autoStart = true;
 #   extraLabels = ["sentry"];
 # };


  # ── llama.cpp inference server (auto-start on boot) ──────────────
  systemd.services.llama-server = {
    enable = true;
    description = "llama.cpp Vulkan inference server (Qwen3.5-4B on RX 5600 XT)";
    wantedBy = ["multi-user.target"];
    after = ["network.target" "systemd-modules-load.service"];
    
    serviceConfig = {
      Type = "simple";
      User = "j_kro";
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
      Environment = [
        "LD_LIBRARY_PATH=${pkgs.vulkan-loader}/lib"
      ];
      ExecStart = ''
        ${llama-cpp-vk}/bin/llama-server \
          --model /home/j_kro/models/Qwen3.5-4B-Q4_K_M.gguf \
          --host 0.0.0.0 \
          --port 8001 \
          --ctx-size 16384 \
          --n-gpu-layers 99 \
          --parallel 2 \
          --no-mmap \
          --temp 0.7 \
          --embeddings \
          --pooling mean
      '';
      Restart = "on-failure";
      RestartSec = 10;
      TimeoutStartSec = 120;
    };
  };

  # ── Fix IPv6 DAD flood — disable privacy extensions that cause conflicts ──
  boot.kernel.sysctl = {
    "net.ipv6.conf.eth0.accept_ra_defrtr" = lib.mkForce 0;
    "net.ipv6.conf.eth0.use_tempaddr" = lib.mkForce 0;
  };
}

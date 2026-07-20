# Agenix Secrets Registry
#
# Central registry of ALL age.secrets declarations across the cluster.
# This module serves as the single source of truth for which secrets
# are deployed to which hosts.
#
# SECRET DEPLOYMENT RULES:
# 1. Each secret must be declared with age.secrets.<name> in the host config
# 2. Secrets are transferred to hosts via Colmena deployment
# 3. Hosts can only decrypt secrets that include their host key in secrets.nix
#
# HOW TO ADD A NEW SECRET:
# 1. Create encrypted file: agenix -e secrets/my-secret.age
# 2. Add publicKeys mapping to secrets.nix (both path variants)
# 3. Declare in this registry (see pattern below)
# 4. Enable in host configuration.nix (see host-specific sections)
#
# FILE STRUCTURE:
# - /etc/nixos/secrets/*.age        - Encrypted secret files
# - /etc/nixos/secrets.nix          - Maps secrets to public keys (who can decrypt)
# - This module                      - Declares where secrets are deployed (age.secrets.*)
# - hosts/*/configuration.nix       - Enables specific secrets per host
#
# RUNTIME LOCATIONS:
# - Decrypted secrets appear at: /run/secrets/<secret-name>
# - Permissions are set per-secret (mode, owner, group)
#
{
  config,
  lib,
  inputs,
  ...
}:
let
  inherit (lib) mkOption types mkIf;
in
{
  options.services.sops-secrets-registry = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable centralized agenix secrets registry";
    };
    # Per-host secret selections
    # Each host can enable only the secrets it needs
    aiServices = mkOption {
      type = types.bool;
      default = false;
      description = "Enable AI service API keys (HuggingFace, LM Studio, ZAI, etc.)";
    };
    monitoring = mkOption {
      type = types.bool;
      default = false;
      description = "Enable monitoring secrets (Grafana, Sentry)";
    };
    storage = mkOption {
      type = types.bool;
      default = false;
      description = "Enable storage secrets (Garage S3, RPC)";
    };
    mining = mkOption {
      type = types.bool;
      default = false;
      description = "Enable mining control secrets (XMRig API tokens)";
    };
    cloud = mkOption {
      type = types.bool;
      default = false;
      description = "Enable cloud service secrets (Tailscale, Cloudflare)";
    };
    selfHosting = mkOption {
      type = types.bool;
      default = false;
      description = "Enable self-hosted service secrets (Nextcloud, Vaultwarden)";
    };
    # Kubernetes-specific secrets
    kubernetes = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Kubernetes cluster secrets";
    };
  };
  config = mkIf config.services.sops-secrets-registry.enable {

    # AI SERVICE API KEYS

    age.secrets = lib.mkMerge [
      # AI Services - Zephyr primary
      (lib.mkIf config.services.sops-secrets-registry.aiServices {
        # LM Studio API key - Local LLM backend
        #        lm-studio-api-key = {
        #          file = "${inputs.self}/secrets/lm-studio-api-key.age";
        #          mode = "440";
        #          owner = "j_kro";
        #          group = "users";
        #        };
        # Hugging Face token - AI model downloads
        huggingface-token = {
          file = "${inputs.self}/secrets/huggingface-token.age";
          mode = "440";
          owner = "j_kro";
          group = "users";
        };
        # ZAI API key - Coding assistant API
        zai-api-key = {
          file = "${inputs.self}/secrets/zai-api-key.age";
          mode = "440";
          owner = "j_kro";
          group = "users";
        };
        # Pollinations API key - Free AI services
        pollinations-api-key = {
          file = "${inputs.self}/secrets/pollinations-api-key.age";
          mode = "440";
          owner = "j_kro";
          group = "users";
        };
        # Kilo API key - Additional AI service
        kilo-api-key = {
          file = "${inputs.self}/secrets/kilo-api-key.age";
          mode = "440";
          owner = "j_kro";
          group = "users";
        };
        # NVIDIA NIM API key - Free LLM endpoints (100+ models via build.nvidia.com)
        nvidia-api-key = {
          file = "${inputs.self}/secrets/nvidia-api-key.age";
          mode = "440";
          owner = "j_kro";
          group = "users";
        };
        # Context7 API key - Documentation search
        context7-api-key = {
          file = "${inputs.self}/secrets/context7-api-key.age";
          mode = "440";
          owner = "j_kro";
          group = "users";
        };
        # Gemini API key - Google AI for onetool ground search
        gemini-api-key = {
          file = "${inputs.self}/secrets/gemini-api-key.age";
          mode = "440";
          owner = "j_kro";
          group = "users";
        };
        # OpenRouter API key - Multi-provider LLM routing (Hermes, Open WebUI)
        # DISABLED: secrets/openrouter-api-key.age does not exist
        # openrouter-api-key = {
        #   file = "${inputs.self}/secrets/openrouter-api-key.age";
        #   mode = "440";
        #   owner = "j_kro";
        #   group = "users";
        # };
        # Anthropic API key - For autoresearch skill optimization
        # DISABLED: File does not exist, commented out to prevent build failure
        # anthropic-api-key = {
        #   file = "${inputs.self}/secrets/anthropic-api-key.age";
        #   mode = "440";
        #   owner = "j_kro";
        #   group = "users";
        # };
        # Spacebot Telegram token - AI agent integration
        spacebot-telegram-token = {
          file = "${inputs.self}/secrets/spacebot-telegram-token.age";
          mode = "440";
          owner = "j_kro";
          group = "users";
        };
      })
      # Monitoring Secrets
      (lib.mkIf config.services.sops-secrets-registry.monitoring {
        # Grafana admin password
        grafana-admin = {
          file = "${inputs.self}/secrets/grafana-admin.age";
          mode = "440";
          owner = "grafana";
          group = "grafana";
        };
      })
      # Storage Secrets (Garage S3 cluster)
      (lib.mkIf config.services.sops-secrets-registry.storage {
        # Garage RPC secret - Cluster authentication
        # Only define if garage service is actually enabled on this host
        garage-rpc-secret = lib.mkIf config.services.garage-cluster.enable {
          file = "${inputs.self}/secrets/garage-rpc-secret.age";
          mode = "440";
          owner = "garage";
          group = "garage";
        };
        # Garage S3 admin secret key - available on all hosts that need S3 access
        garage-s3-secret-key = {
          file = "${inputs.self}/secrets/garage-s3-secret-key.age";
          mode = "440";
          owner = "root";
          group = "wheel";
        };
      })
      # Mining Control Secrets
      (lib.mkIf config.services.sops-secrets-registry.mining {
        # XMRig primary API token (pause-able instance)
        xmrig-api-token = {
          file = "${inputs.self}/secrets/xmrig-api-token.age";
          mode = "440";
          owner = "mining";
          group = "mining";
        };
        # XMRig always-on instance API token
        xmrig-always-api-token = {
          file = "${inputs.self}/secrets/xmrig-always-api-token.age";
          mode = "440";
          owner = "mining";
          group = "mining";
        };
        # XMRig flexible instance API token
        xmrig-flexible-api-token = {
          file = "${inputs.self}/secrets/xmrig-flexible-api-token.age";
          mode = "440";
          owner = "mining";
          group = "mining";
        };
      })
      # Cloud Service Secrets
      (lib.mkIf config.services.sops-secrets-registry.cloud {
        # Tailscale API key
        tailscale-api-key = {
          file = "${inputs.self}/secrets/tailscale-api-key.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
        # Cloudflare Tunnel token
        cloudflared-token = {
          file = "${inputs.self}/secrets/cloudflared-token.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
        # Cloudflare API token - DNS and cache operations
        cloudflare-api-token = {
          file = "${inputs.self}/secrets/cloudflare-api-token.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
      })
      # Self-Hosted Service Secrets
      (lib.mkIf config.services.sops-secrets-registry.selfHosting {
        # Nextcloud admin password
        nextcloud-admin = {
          file = "${inputs.self}/secrets/nextcloud-admin.age";
          mode = "440";
          owner = "nextcloud";
          group = "nextcloud";
        };
        # Vaultwarden admin token
        vaultwarden-admin-token = {
          file = "${inputs.self}/secrets/vaultwarden-admin-token.age";
          mode = "440";
          owner = "vaultwarden";
          group = "vaultwarden";
        };
      })
      # Kubernetes/k3s Secrets
      (lib.mkIf config.services.sops-secrets-registry.kubernetes {
        # k3s cluster token - used for server/agent authentication
        # NOTE: Bootstrap secret only, not consumed by any running module
        k3s-cluster-token = {
          file = "${inputs.self}/secrets/k3s-cluster-token.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
      })
    ];
  };
}

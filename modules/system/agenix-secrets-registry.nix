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
  options.services.agenix-secrets-registry = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable centralized agenix secrets registry";
    };
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
    kubernetes = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Kubernetes cluster secrets";
    };
  };
  config = mkIf config.services.agenix-secrets-registry.enable {


    age.secrets = lib.mkMerge [
      (lib.mkIf config.services.agenix-secrets-registry.aiServices {
        huggingface-token = {
          file = "${inputs.self}/secrets/huggingface-token.age";
          mode = "440";
          owner = "j_kro";
          group = "users";
        };
        zai-api-key = {
          file = "${inputs.self}/secrets/zai-api-key.age";
          mode = "440";
          owner = "j_kro";
          group = "users";
        };
        pollinations-api-key = {
          file = "${inputs.self}/secrets/pollinations-api-key.age";
          mode = "440";
          owner = "j_kro";
          group = "users";
        };
        kilo-api-key = {
          file = "${inputs.self}/secrets/kilo-api-key.age";
          mode = "440";
          owner = "j_kro";
          group = "users";
        };
        nvidia-api-key = {
          file = "${inputs.self}/secrets/nvidia-api-key.age";
          mode = "440";
          owner = "j_kro";
          group = "users";
        };
        context7-api-key = {
          file = "${inputs.self}/secrets/context7-api-key.age";
          mode = "440";
          owner = "j_kro";
          group = "users";
        };
        gemini-api-key = {
          file = "${inputs.self}/secrets/gemini-api-key.age";
          mode = "440";
          owner = "j_kro";
          group = "users";
        };

      })
      (lib.mkIf config.services.agenix-secrets-registry.monitoring {
        grafana-admin = {
          file = "${inputs.self}/secrets/grafana-admin.age";
          mode = "440";
          owner = "grafana";
          group = "grafana";
        };
      })
      (lib.mkIf config.services.agenix-secrets-registry.storage {
        garage-rpc-secret = lib.mkIf config.services.garage-cluster.enable {
          file = "${inputs.self}/secrets/garage-rpc-secret.age";
          mode = "440";
          owner = "garage";
          group = "garage";
        };
        garage-s3-secret-key = {
          file = "${inputs.self}/secrets/garage-s3-secret-key.age";
          mode = "440";
          owner = "root";
          group = "wheel";
        };
      })
      (lib.mkIf config.services.agenix-secrets-registry.mining {
        xmrig-api-token = {
          file = "${inputs.self}/secrets/xmrig-api-token.age";
          mode = "440";
          owner = "mining";
          group = "mining";
        };
        xmrig-always-api-token = {
          file = "${inputs.self}/secrets/xmrig-always-api-token.age";
          mode = "440";
          owner = "mining";
          group = "mining";
        };
        xmrig-flexible-api-token = {
          file = "${inputs.self}/secrets/xmrig-flexible-api-token.age";
          mode = "440";
          owner = "mining";
          group = "mining";
        };
      })
      (lib.mkIf config.services.agenix-secrets-registry.cloud {
        tailscale-api-key = {
          file = "${inputs.self}/secrets/tailscale-api-key.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
        cloudflared-token = {
          file = "${inputs.self}/secrets/cloudflared-token.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
        cloudflare-api-token = {
          file = "${inputs.self}/secrets/cloudflare-api-token.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
      })
      (lib.mkIf config.services.agenix-secrets-registry.selfHosting {
        nextcloud-admin = {
          file = "${inputs.self}/secrets/nextcloud-admin.age";
          mode = "440";
          owner = "nextcloud";
          group = "nextcloud";
        };
        vaultwarden-admin-token = {
          file = "${inputs.self}/secrets/vaultwarden-admin-token.age";
          mode = "440";
          owner = "vaultwarden";
          group = "vaultwarden";
        };
      })
      (lib.mkIf config.services.agenix-secrets-registry.kubernetes {
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

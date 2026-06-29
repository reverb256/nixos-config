{ config, lib, inputs, ... }: let
  inherit (lib) mkOption types mkIf;
in {
  options.services.sops-secrets-registry = {
    enable = mkOption { type = types.bool; default = false; };
    aiServices = mkOption { type = types.bool; default = false; };
    kubernetes = mkOption { type = types.bool; default = false; };
    cloud = mkOption { type = types.bool; default = false; };
    monitoring = mkOption { type = types.bool; default = false; };
    mining = mkOption { type = types.bool; default = false; };
    storage = mkOption { type = types.bool; default = false; };
    automation = mkOption { type = types.bool; default = false; };
    selfHosting = mkOption { type = types.bool; default = false; };
    ci = mkOption { type = types.bool; default = false; };
  };

  config = mkIf config.services.sops-secrets-registry.enable {
    sops = {
      defaultSopsFile = "${inputs.self}/secrets/ai/nvidia-api-key.yaml";
      defaultSopsFormat = "binary";
      age.keyFile = "/etc/nixos/.age/key.txt";
      secrets = lib.mkMerge [
        (mkIf config.services.sops-secrets-registry.aiServices {
          "default/activepieces-api-key" = {
            sopsFile = "${inputs.self}/secrets/default/activepieces-api-key.yaml";
            path = "/run/secrets/activepieces-api-key";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "default/activepieces-encryption-key" = {
            sopsFile = "${inputs.self}/secrets/default/activepieces-encryption-key.yaml";
            path = "/run/secrets/activepieces-encryption-key";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "default/activepieces-jwt-secret" = {
            sopsFile = "${inputs.self}/secrets/default/activepieces-jwt-secret.yaml";
            path = "/run/secrets/activepieces-jwt-secret";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
          "ai/cachix-token" = {
            sopsFile = "${inputs.self}/secrets/ai/cachix-token.yaml";
            path = "/run/secrets/cachix-token";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
          "ai/context7-api-key" = {
            sopsFile = "${inputs.self}/secrets/ai/context7-api-key.yaml";
            path = "/run/secrets/context7-api-key";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "default/garnix-password" = {
            sopsFile = "${inputs.self}/secrets/default/garnix-password.yaml";
            path = "/run/secrets/garnix-password";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
          "ai/gemini-api-key" = {
            sopsFile = "${inputs.self}/secrets/ai/gemini-api-key.yaml";
            path = "/run/secrets/gemini-api-key";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "ai/hermes-api-server-key" = {
            sopsFile = "${inputs.self}/secrets/ai/hermes-api-server-key.yaml";
            path = "/run/secrets/hermes-api-server-key";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "ai/hermes-webui-password" = {
            sopsFile = "${inputs.self}/secrets/ai/hermes-webui-password.yaml";
            path = "/run/secrets/hermes-webui-password";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
          "ai/huggingface-token" = {
            sopsFile = "${inputs.self}/secrets/ai/huggingface-token.yaml";
            path = "/run/secrets/huggingface-token";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
          "ai/katzilla-api-key" = {
            sopsFile = "${inputs.self}/secrets/ai/katzilla-api-key.yaml";
            path = "/run/secrets/katzilla-api-key";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "ai/kilo-api-key" = {
            sopsFile = "${inputs.self}/secrets/ai/kilo-api-key.yaml";
            path = "/run/secrets/kilo-api-key";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "ai/localmaxxing-api-key" = {
            sopsFile = "${inputs.self}/secrets/ai/localmaxxing-api-key.yaml";
            path = "/run/secrets/localmaxxing-api-key";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "ai/neocities-api-key" = {
            sopsFile = "${inputs.self}/secrets/ai/neocities-api-key.yaml";
            path = "/run/secrets/neocities-api-key";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "ai/nvidia-api-key" = {
            sopsFile = "${inputs.self}/secrets/ai/nvidia-api-key.yaml";
            path = "/run/secrets/nvidia-api-key";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "ai/opencode-api-key" = {
            sopsFile = "${inputs.self}/secrets/ai/opencode-api-key.yaml";
            path = "/run/secrets/opencode-api-key";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "ai/opencode-go-api-key" = {
            sopsFile = "${inputs.self}/secrets/ai/opencode-go-api-key.yaml";
            path = "/run/secrets/opencode-go-api-key";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "ai/pollinations-api-key" = {
            sopsFile = "${inputs.self}/secrets/ai/pollinations-api-key.yaml";
            path = "/run/secrets/pollinations-api-key";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "ai/xai-access-token" = {
            sopsFile = "${inputs.self}/secrets/ai/xai-access-token.yaml";
            path = "/run/secrets/xai-access-token";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
          "ai/zai-api-key" = {
            sopsFile = "${inputs.self}/secrets/ai/zai-api-key.yaml";
            path = "/run/secrets/zai-api-key";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "ai/hermes-env" = {
            sopsFile = "${inputs.self}/secrets/ai/hermes-env.env";
            path = "/run/secrets/hermes-env";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
        })
        (mkIf config.services.sops-secrets-registry.kubernetes {
          "k8s/ai-gateway-zai-api-key" = {
            sopsFile = "${inputs.self}/secrets/k8s/ai-gateway-zai-api-key.yaml";
            path = "/run/secrets/ai-gateway-zai-api-key";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "k8s/casdoor-hermes-jwt" = {
            sopsFile = "${inputs.self}/secrets/k8s/casdoor-hermes-jwt.yaml";
            path = "/run/secrets/casdoor-hermes-jwt";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "k8s/central-auth-client-secret" = {
            sopsFile = "${inputs.self}/secrets/k8s/central-auth-client-secret.yaml";
            path = "/run/secrets/central-auth-client-secret";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
          "k8s/central-auth-cookie-secret" = {
            sopsFile = "${inputs.self}/secrets/k8s/central-auth-cookie-secret.yaml";
            path = "/run/secrets/central-auth-cookie-secret";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
          "infra/cns-ssh-key" = {
            sopsFile = "${inputs.self}/secrets/infra/cns-ssh-key.yaml";
            path = "/run/secrets/cns-ssh-key";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "k8s/frostbite-postgres" = {
            sopsFile = "${inputs.self}/secrets/k8s/frostbite-postgres.yaml";
            path = "/run/secrets/frostbite-postgres";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "infra/initrd-ssh-host-key-forge" = {
            sopsFile = "${inputs.self}/secrets/infra/initrd-ssh-host-key-forge.yaml";
            path = "/run/secrets/initrd-ssh-host-key-forge";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "infra/initrd-ssh-host-key-nexus" = {
            sopsFile = "${inputs.self}/secrets/infra/initrd-ssh-host-key-nexus.yaml";
            path = "/run/secrets/initrd-ssh-host-key-nexus";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "infra/initrd-ssh-host-key-sentry" = {
            sopsFile = "${inputs.self}/secrets/infra/initrd-ssh-host-key-sentry.yaml";
            path = "/run/secrets/initrd-ssh-host-key-sentry";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "infra/initrd-ssh-host-key-zephyr" = {
            sopsFile = "${inputs.self}/secrets/infra/initrd-ssh-host-key-zephyr.yaml";
            path = "/run/secrets/initrd-ssh-host-key-zephyr";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "k8s/k3s-cluster-token" = {
            sopsFile = "${inputs.self}/secrets/k8s/k3s-cluster-token.yaml";
            path = "/run/secrets/k3s-cluster-token";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
          "k8s/mission-control-api-key" = {
            sopsFile = "${inputs.self}/secrets/k8s/mission-control-api-key.yaml";
            path = "/run/secrets/mission-control-api-key";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "k8s/mission-control-auth-pass" = {
            sopsFile = "${inputs.self}/secrets/k8s/mission-control-auth-pass.yaml";
            path = "/run/secrets/mission-control-auth-pass";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "k8s/searxng-secret-key" = {
            sopsFile = "${inputs.self}/secrets/k8s/searxng-secret-key.yaml";
            path = "/run/secrets/searxng-secret-key";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
          "infra/ssh-ca-key" = {
            sopsFile = "${inputs.self}/secrets/infra/ssh-ca-key.yaml";
            path = "/run/secrets/ssh-ca-key";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "infra/switch-admin" = {
            sopsFile = "${inputs.self}/secrets/infra/switch-admin.yaml";
            path = "/run/secrets/switch-admin";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
        })
        (mkIf config.services.sops-secrets-registry.cloud {
          "cloud/cloudflare-api-token" = {
            sopsFile = "${inputs.self}/secrets/cloud/cloudflare-api-token.yaml";
            path = "/run/secrets/cloudflare-api-token";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
          "cloud/cloudflare-global-api-key" = {
            sopsFile = "${inputs.self}/secrets/cloud/cloudflare-global-api-key.yaml";
            path = "/run/secrets/cloudflare-global-api-key";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "cloud/cloudflared-token" = {
            sopsFile = "${inputs.self}/secrets/cloud/cloudflared-token.yaml";
            path = "/run/secrets/cloudflared-token";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
          "cloud/tailscale-api-key" = {
            sopsFile = "${inputs.self}/secrets/cloud/tailscale-api-key.yaml";
            path = "/run/secrets/tailscale-api-key";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "cloud/tailscale-oauth" = {
            sopsFile = "${inputs.self}/secrets/cloud/tailscale-oauth.yaml";
            path = "/run/secrets/tailscale-oauth";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
        })
        (mkIf config.services.sops-secrets-registry.monitoring {
          "monitoring/grafana-admin" = {
            sopsFile = "${inputs.self}/secrets/monitoring/grafana-admin.yaml";
            path = "/run/secrets/grafana-admin";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "monitoring/grafana-admin-password" = {
            sopsFile = "${inputs.self}/secrets/monitoring/grafana-admin-password.yaml";
            path = "/run/secrets/grafana-admin-password";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
          "monitoring/grafana-oidc-client-secret" = {
            sopsFile = "${inputs.self}/secrets/monitoring/grafana-oidc-client-secret.yaml";
            path = "/run/secrets/grafana-oidc-client-secret";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
        })
        (mkIf config.services.sops-secrets-registry.mining {
          "mining/xmrig-always-api-token" = {
            sopsFile = "${inputs.self}/secrets/mining/xmrig-always-api-token.yaml";
            path = "/run/secrets/xmrig-always-api-token";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
          "mining/xmrig-api-token" = {
            sopsFile = "${inputs.self}/secrets/mining/xmrig-api-token.yaml";
            path = "/run/secrets/xmrig-api-token";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
          "mining/xmrig-flexible-api-token" = {
            sopsFile = "${inputs.self}/secrets/mining/xmrig-flexible-api-token.yaml";
            path = "/run/secrets/xmrig-flexible-api-token";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
          "mining/xmrig-proxy-api-token" = {
            sopsFile = "${inputs.self}/secrets/mining/xmrig-proxy-api-token.yaml";
            path = "/run/secrets/xmrig-proxy-api-token";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
        })
        (mkIf config.services.sops-secrets-registry.storage {
          "storage/garage-metrics-token" = {
            sopsFile = "${inputs.self}/secrets/storage/garage-metrics-token.yaml";
            path = "/run/secrets/garage-metrics-token";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
          "storage/garage-rpc-secret" = {
            sopsFile = "${inputs.self}/secrets/storage/garage-rpc-secret.yaml";
            path = "/run/secrets/garage-rpc-secret";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
          "storage/garage-s3-access-key-id" = {
            sopsFile = "${inputs.self}/secrets/storage/garage-s3-access-key-id.yaml";
            path = "/run/secrets/garage-s3-access-key-id";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "storage/garage-s3-secret-key" = {
            sopsFile = "${inputs.self}/secrets/storage/garage-s3-secret-key.yaml";
            path = "/run/secrets/garage-s3-secret-key";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
        })
        (mkIf config.services.sops-secrets-registry.automation {
          "automation/n8n-admin-password" = {
            sopsFile = "${inputs.self}/secrets/automation/n8n-admin-password.yaml";
            path = "/run/secrets/n8n-admin-password";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
          "automation/n8n-api-key" = {
            sopsFile = "${inputs.self}/secrets/automation/n8n-api-key.yaml";
            path = "/run/secrets/n8n-api-key";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "automation/n8n-encryption-key" = {
            sopsFile = "${inputs.self}/secrets/automation/n8n-encryption-key.yaml";
            path = "/run/secrets/n8n-encryption-key";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
        })
        (mkIf config.services.sops-secrets-registry.selfHosting {
          "selfhosting/nextcloud-admin" = {
            sopsFile = "${inputs.self}/secrets/selfhosting/nextcloud-admin.yaml";
            path = "/run/secrets/nextcloud-admin";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "selfhosting/rclone-config" = {
            sopsFile = "${inputs.self}/secrets/selfhosting/rclone-config.yaml";
            path = "/run/secrets/rclone-config";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "selfhosting/vaultwarden-admin-token" = {
            sopsFile = "${inputs.self}/secrets/selfhosting/vaultwarden-admin-token.yaml";
            path = "/run/secrets/vaultwarden-admin-token";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
          "selfhosting/vaultwarden-oidc-client-secret" = {
            sopsFile = "${inputs.self}/secrets/selfhosting/vaultwarden-oidc-client-secret.yaml";
            path = "/run/secrets/vaultwarden-oidc-client-secret";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
        })
        (mkIf config.services.sops-secrets-registry.ci {
          "ci/gitea-runner-token" = {
            sopsFile = "${inputs.self}/secrets/ci/gitea-runner-token.yaml";
            path = "/run/secrets/gitea-runner-token";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
          "ci/gitea-runner-url" = {
            sopsFile = "${inputs.self}/secrets/ci/gitea-runner-url.yaml";
            path = "/run/secrets/gitea-runner-url";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "ci/github-runner-pat" = {
            sopsFile = "${inputs.self}/secrets/ci/github-runner-pat.yaml";
            path = "/run/secrets/github-runner-pat";
            format = "binary";
            mode = "0444";
            owner = "j_kro";
            group = "users";
          };
          "ci/github-token" = {
            sopsFile = "${inputs.self}/secrets/ci/github-token.yaml";
            path = "/run/secrets/github-token";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
          "ci/npm-token" = {
            sopsFile = "${inputs.self}/secrets/ci/npm-token.yaml";
            path = "/run/secrets/npm-token";
            format = "binary";
            mode = "0444";
            owner = "root";
            group = "root";
          };
        })
      ];
    };
  };
}
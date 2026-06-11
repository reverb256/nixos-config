{
  config,
  lib,
  inputs,
  ...
}: let
  inherit (lib) mkOption types mkIf;
in {
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
    automation = mkOption {
      type = types.bool;
      default = false;
      description = "Enable automation service secrets (n8n, Activepieces)";
    };
    selfHosting = mkOption {
      type = types.bool;
      default = false;
      description = "Enable self-hosted service secrets (Nextcloud, Vaultwarden, Casdoor)";
    };
    ci = mkOption {
      type = types.bool;
      default = false;
      description = "Enable CI/CD secrets (Garnix, etc)";
    };
    kubernetes = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Kubernetes cluster secrets";
    };
    cns = mkOption {
      type = types.bool;
      default = false;
      description = "Enable CNS (Central NixOS Secret) SSH key for automatic secret distribution";
    };
    initrdRecovery = mkOption {
      type = types.bool;
      default = false;
      description = "Enable initrd SSH recovery host keys";
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
        xai-access-token = {
          file = "${inputs.self}/secrets/xai-access-token.age";
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
        katzilla-api-key = {
          file = "${inputs.self}/secrets/katzilla-api-key.age";
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
        # openrouter-api-key removed — no longer used
        localmaxxing-api-key = {
          file = "${inputs.self}/secrets/localmaxxing-api-key.age";
          mode = "440";
          owner = "j_kro";
          group = "users";
        };
        # hermes-webui-password — archived (hermes-webui project deleted 2026-05-16)
        hermes-api-server-key = {
          file = "${inputs.self}/secrets/hermes-api-server-key.age";
          mode = "440";
          owner = "j_kro";
          group = "users";
        };
        github-token = {
          file = "${inputs.self}/secrets/github-token.age";
          mode = "440";
          owner = "j_kro";
          group = "users";
        };
        neocities-api-key = {
          file = "${inputs.self}/secrets/neocities-api-key.age";
          mode = "440";
          owner = "j_kro";
          group = "users";
        };
        opencode-go-api-key = {
          file = "${inputs.self}/secrets/opencode-go-api-key.age";
          mode = "440";
          owner = "j_kro";
          group = "users";
        };
        opencode-api-key = {
          file = "${inputs.self}/secrets/opencode-api-key.age";
          mode = "440";
          owner = "j_kro";
          group = "users";
        };
        cachix-token = {
          file = "${inputs.self}/secrets/cachix-token.age";
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
        };
        garage-s3-secret-key = {
          file = "${inputs.self}/secrets/garage-s3-secret-key.age";
          mode = "440";
          owner = "root";
          group = "wheel";
        };
        # TODO: Run `agenix -e secrets/garage-metrics-token.age` to create this file
        garage-metrics-token = {
          file = "${inputs.self}/secrets/garage-metrics-token.age";
          mode = "440";
        };
        # TODO: Run `agenix -e secrets/garage-s3-access-key-id.age` to create this file
        garage-s3-access-key-id = {
          file = "${inputs.self}/secrets/garage-s3-access-key-id.age";
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
          owner = "j_kro";
          group = "users";
        };
        cloudflare-global-api-key = {
          file = "${inputs.self}/secrets/cloudflare-global-api-key.age";
          mode = "440";
          owner = "j_kro";
          group = "users";
        };
      })
      (lib.mkIf config.services.agenix-secrets-registry.ci {
        # TODO: Run `agenix -e secrets/garnix-password.age` to create this file
        garnix-password = {
          file = "${inputs.self}/secrets/garnix-password.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
        npm-token = {
          file = "${inputs.self}/secrets/npm-token.age";
          mode = "440";
          owner = "j_kro";
          group = "users";
        };
      })
      (lib.mkIf config.services.agenix-secrets-registry.selfHosting {
        nextcloud-admin = {
          file = "${inputs.self}/secrets/nextcloud-admin.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
        vaultwarden-admin-token = {
          file = "${inputs.self}/secrets/vaultwarden-admin-token.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
        rclone-config = {
          file = "${inputs.self}/secrets/rclone-config.age";
          mode = "400";
          owner = "root";
          group = "root";
        };
      })
      (lib.mkIf config.services.agenix-secrets-registry.kubernetes {
        k3s-cluster-token = {
          file = "${inputs.self}/secrets/k3s-cluster-token.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
        # K8s namespace-scoped secrets (applied via kubectl-apply-k8s-secrets service)
        searxng-secret-key = {
          file = "${inputs.self}/secrets/searxng-secret-key.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
        mission-control-auth-pass = {
          file = "${inputs.self}/secrets/mission-control-auth-pass.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
        mission-control-api-key = {
          file = "${inputs.self}/secrets/mission-control-api-key.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
        ai-gateway-zai-api-key = {
          file = "${inputs.self}/secrets/ai-gateway-zai-api-key.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
        grafana-admin-password = {
          file = "${inputs.self}/secrets/grafana-admin-password.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
        xmrig-proxy-api-token = {
          file = "${inputs.self}/secrets/xmrig-proxy-api-token.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
        casdoor-hermes-jwt = {
          file = "${inputs.self}/secrets/casdoor-hermes-jwt.age";
          mode = "440";
          owner = "j_kro";
          group = "users";
        };
        grafana-oidc-client-secret = {
          file = "${inputs.self}/secrets/grafana-oidc-client-secret.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
        openwebui-oidc-client-secret = {
          file = "${inputs.self}/secrets/openwebui-oidc-client-secret.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
        vaultwarden-oidc-client-secret = {
          file = "${inputs.self}/secrets/vaultwarden-oidc-client-secret.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
        central-auth-client-secret = {
          file = "${inputs.self}/secrets/central-auth-client-secret.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
        central-auth-cookie-secret = {
          file = "${inputs.self}/secrets/central-auth-cookie-secret.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
        # Tailscale operator OAuth credentials — migrated from hardcoded in kubernetes/modules/tailscale.nix
        tailscale-oauth = {
          file = "${inputs.self}/secrets/tailscale-oauth.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
        # Frostbite Gazette postgres password — migrated from hardcoded in kubernetes/modules/frostbite-gazette.nix
        frostbite-postgres = {
          file = "${inputs.self}/secrets/frostbite-postgres.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
        # Kagent postgres password — migrated from hardcoded in kubernetes/modules/kagent.nix
        kagent-postgres = {
          file = "${inputs.self}/secrets/kagent-postgres.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
      })
      (lib.mkIf config.services.agenix-secrets-registry.automation {
        n8n-admin-password = {
          file = "${inputs.self}/secrets/n8n-admin-password.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
        n8n-encryption-key = {
          file = "${inputs.self}/secrets/n8n-encryption-key.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
        n8n-api-key = {
          file = "${inputs.self}/secrets/n8n-api-key.age";
          mode = "440";
          owner = "root";
          group = "root";
        };
      })
      (lib.mkIf config.services.agenix-secrets-registry.cns {
        cns-ssh-key = {
          file = "${inputs.self}/secrets/cns-ssh-key.age";
          mode = "600";
          owner = "cluster-mesh";
          group = "cluster-mesh";
        };
      })
      (lib.mkIf config.services.agenix-secrets-registry.initrdRecovery {
        initrd-ssh-host-key = {
          file = "${inputs.self}/secrets/initrd-ssh-host-key-${config.networking.hostName}.age";
          mode = "400";
          owner = "root";
          group = "root";
        };
      })
    ];
  };
}

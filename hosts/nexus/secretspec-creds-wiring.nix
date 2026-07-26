{
  # ── aiServices ──────────────────────────────────────────────
  ACTIVEPIECES_API_KEY = { path = "/run/secrets/activepieces-api-key"; file = "default/activepieces-api-key.yaml"; owner = "j_kro"; group = "users"; };
  ACTIVEPIECES_ENCRYPTION_KEY = { path = "/run/secrets/activepieces-encryption-key"; file = "default/activepieces-encryption-key.yaml"; owner = "j_kro"; group = "users"; };
  ACTIVEPIECES_JWT_SECRET = { path = "/run/secrets/activepieces-jwt-secret"; file = "default/activepieces-jwt-secret.yaml"; owner = "root"; };
  CACHIX_TOKEN = { path = "/run/secrets/cachix-token"; file = "ai/cachix-token.yaml"; owner = "root"; };
  CONTEXT7_API_KEY = { path = "/run/secrets/context7-api-key"; file = "ai/context7-api-key.yaml"; owner = "j_kro"; group = "users"; };
  EXA_API_KEY = { path = "/run/secrets/exa-api-key"; file = "ai/exa-api-key.yaml"; owner = "j_kro"; group = "users"; };
  GEMINI_API_KEY = { path = "/run/secrets/gemini-api-key"; file = "ai/gemini-api-key.yaml"; owner = "j_kro"; group = "users"; };
  HERMES_API_SERVER_KEY = { path = "/run/secrets/hermes-api-server-key"; file = "ai/hermes-api-server-key.yaml"; owner = "j_kro"; group = "users"; };
  HERMES_WEBUI_PASSWORD = { path = "/run/secrets/hermes-webui-password"; file = "ai/hermes-webui-password.yaml"; owner = "root"; };
  HUGGINGFACE_TOKEN = { path = "/run/secrets/huggingface-token"; file = "ai/huggingface-token.yaml"; owner = "root"; };
  KATZILLA_API_KEY = { path = "/run/secrets/katzilla-api-key"; file = "ai/katzilla-api-key.yaml"; owner = "j_kro"; group = "users"; };
  KILO_API_KEY = { path = "/run/secrets/kilo-api-key"; file = "ai/kilo-api-key.yaml"; owner = "j_kro"; group = "users"; };
  LOCALMAXXING_API_KEY = { path = "/run/secrets/localmaxxing-api-key"; file = "ai/localmaxxing-api-key.yaml"; owner = "j_kro"; group = "users"; };
  NEOCITIES_API_KEY = { path = "/run/secrets/neocities-api-key"; file = "ai/neocities-api-key.yaml"; owner = "j_kro"; group = "users"; };
  NVIDIA_API_KEY = { path = "/run/secrets/nvidia-api-key"; file = "ai/nvidia-api-key.yaml"; owner = "j_kro"; group = "users"; };
  OPENCODE_ZEN_API_KEY = { path = "/run/secrets/opencode-api-key"; file = "ai/opencode-api-key.yaml"; owner = "j_kro"; group = "users"; };
  OPENCODE_GO_API_KEY = { path = "/run/secrets/opencode-go-api-key"; file = "ai/opencode-go-api-key.yaml"; owner = "j_kro"; group = "users"; };
  POLLINATIONS_API_KEY = { path = "/run/secrets/pollinations-api-key"; file = "ai/pollinations-api-key.yaml"; owner = "j_kro"; group = "users"; };
  XAI_ACCESS_TOKEN = { path = "/run/secrets/xai-access-token"; file = "ai/xai-access-token.yaml"; owner = "root"; };

  # ── kubernetes (block 1) ────────────────────────────────────
  CENTRAL_AUTH_CLIENT_SECRET = { path = "/run/secrets/central-auth-client-secret"; file = "k8s/central-auth-client-secret.yaml"; owner = "root"; };
  CENTRAL_AUTH_COOKIE_SECRET = { path = "/run/secrets/central-auth-cookie-secret"; file = "k8s/central-auth-cookie-secret.yaml"; owner = "root"; };
  CNS_SSH_KEY = { path = "/run/secrets/cns-ssh-key"; file = "infra/cns-ssh-key.yaml"; owner = "j_kro"; group = "users"; };
  K3S_ENCRYPTION_KEY = { path = "/run/secrets/k3s-encryption-key"; file = "infra/k3s-encryption-key.json"; owner = "root"; };
  FROSTBITE_POSTGRES = { path = "/run/secrets/frostbite-postgres"; file = "k8s/frostbite-postgres.yaml"; owner = "j_kro"; group = "users"; };
  INITRD_SSH_KEY_FORGE = { path = "/run/secrets/initrd-ssh-host-key-forge"; file = "infra/initrd-ssh-host-key-forge.yaml"; owner = "j_kro"; group = "users"; };
  INITRD_SSH_KEY_NEXUS = { path = "/run/secrets/initrd-ssh-host-key-nexus"; file = "infra/initrd-ssh-host-key-nexus.yaml"; owner = "j_kro"; group = "users"; };
  INITRD_SSH_KEY_SENTRY = { path = "/run/secrets/initrd-ssh-host-key-sentry"; file = "infra/initrd-ssh-host-key-sentry.yaml"; owner = "j_kro"; group = "users"; };
  INITRD_SSH_KEY_ZEPHYR = { path = "/run/secrets/initrd-ssh-host-key-zephyr"; file = "infra/initrd-ssh-host-key-zephyr.yaml"; owner = "j_kro"; group = "users"; };

  # ── kubernetes (block 2) ────────────────────────────────────
  MISSION_CONTROL_API_KEY = { path = "/run/secrets/mission-control-api-key"; file = "k8s/mission-control-api-key.yaml"; owner = "j_kro"; group = "users"; };
  MISSION_CONTROL_AUTH_PASS = { path = "/run/secrets/mission-control-auth-pass"; file = "k8s/mission-control-auth-pass.yaml"; owner = "j_kro"; group = "users"; };
  SEARXNG_SECRET_KEY = { path = "/run/secrets/searxng-secret-key"; file = "k8s/searxng-secret-key.yaml"; owner = "root"; };
  SSH_CA_KEY = { path = "/run/secrets/ssh-ca-key"; file = "infra/ssh-ca-key.yaml"; owner = "j_kro"; group = "users"; };
  SWITCH_ADMIN = { path = "/run/secrets/switch-admin"; file = "infra/switch-admin.yaml"; owner = "j_kro"; group = "users"; };
  K3S_CLUSTER_TOKEN = { path = "/run/secrets/k3s-cluster-token"; file = "k8s/k3s-cluster-token.yaml"; owner = "root"; };

  # ── storage ─────────────────────────────────────────────────
  GARAGE_METRICS_TOKEN = { path = "/run/secrets/garage-metrics-token"; file = "storage/garage-metrics-token.yaml"; owner = "root"; };
  GARAGE_RPC_SECRET = { path = "/run/secrets/garage-rpc-secret"; file = "storage/garage-rpc-secret.yaml"; owner = "root"; };
  GARAGE_ACCESS_KEY = { path = "/run/secrets/garage-s3-access-key-id"; file = "storage/garage-s3-access-key-id.yaml"; owner = "j_kro"; group = "users"; };
  GARAGE_SECRET_KEY = { path = "/run/secrets/garage-s3-secret-key"; file = "storage/garage-s3-secret-key.yaml"; owner = "root"; };
}

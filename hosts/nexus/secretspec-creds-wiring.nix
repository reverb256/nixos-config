{
  # ── aiServices ──────────────────────────────────────────────
  ACTIVEPIECES_API_KEY = { path = "/run/secrets/activepieces-api-key"; owner = "j_kro"; group = "users"; };
  ACTIVEPIECES_ENCRYPTION_KEY = { path = "/run/secrets/activepieces-encryption-key"; owner = "j_kro"; group = "users"; };
  ACTIVEPIECES_JWT_SECRET = { path = "/run/secrets/activepieces-jwt-secret"; owner = "root"; };
  CACHIX_TOKEN = { path = "/run/secrets/cachix-token"; owner = "root"; };
  CONTEXT7_API_KEY = { path = "/run/secrets/context7-api-key"; owner = "j_kro"; group = "users"; };
  EXA_API_KEY = { path = "/run/secrets/exa-api-key"; owner = "j_kro"; group = "users"; };
  GEMINI_API_KEY = { path = "/run/secrets/gemini-api-key"; owner = "j_kro"; group = "users"; };
  HERMES_API_SERVER_KEY = { path = "/run/secrets/hermes-api-server-key"; owner = "j_kro"; group = "users"; };
  HERMES_WEBUI_PASSWORD = { path = "/run/secrets/hermes-webui-password"; owner = "root"; };
  HUGGINGFACE_TOKEN = { path = "/run/secrets/huggingface-token"; owner = "root"; };
  KATZILLA_API_KEY = { path = "/run/secrets/katzilla-api-key"; owner = "j_kro"; group = "users"; };
  KILO_API_KEY = { path = "/run/secrets/kilo-api-key"; owner = "j_kro"; group = "users"; };
  LOCALMAXXING_API_KEY = { path = "/run/secrets/localmaxxing-api-key"; owner = "j_kro"; group = "users"; };
  NEOCITIES_API_KEY = { path = "/run/secrets/neocities-api-key"; owner = "j_kro"; group = "users"; };
  NVIDIA_API_KEY = { path = "/run/secrets/nvidia-api-key"; owner = "j_kro"; group = "users"; };
  OPENCODE_ZEN_API_KEY = { path = "/run/secrets/opencode-api-key"; owner = "j_kro"; group = "users"; };
  OPENCODE_GO_API_KEY = { path = "/run/secrets/opencode-go-api-key"; owner = "j_kro"; group = "users"; };
  POLLINATIONS_API_KEY = { path = "/run/secrets/pollinations-api-key"; owner = "j_kro"; group = "users"; };
  XAI_ACCESS_TOKEN = { path = "/run/secrets/xai-access-token"; owner = "root"; };

  # ── kubernetes (block 1) ────────────────────────────────────
  CASDOOR_HERMES_JWT = { path = "/run/secrets/casdoor-hermes-jwt"; owner = "j_kro"; group = "users"; };
  CENTRAL_AUTH_CLIENT_SECRET = { path = "/run/secrets/central-auth-client-secret"; owner = "root"; };
  CENTRAL_AUTH_COOKIE_SECRET = { path = "/run/secrets/central-auth-cookie-secret"; owner = "root"; };
  CNS_SSH_KEY = { path = "/run/secrets/cns-ssh-key"; owner = "j_kro"; group = "users"; };
  K3S_ENCRYPTION_KEY = { path = "/run/secrets/k3s-encryption-key"; owner = "root"; };
  FROSTBITE_POSTGRES = { path = "/run/secrets/frostbite-postgres"; owner = "j_kro"; group = "users"; };
  INITRD_SSH_KEY_FORGE = { path = "/run/secrets/initrd-ssh-host-key-forge"; owner = "j_kro"; group = "users"; };
  INITRD_SSH_KEY_NEXUS = { path = "/run/secrets/initrd-ssh-host-key-nexus"; owner = "j_kro"; group = "users"; };
  INITRD_SSH_KEY_SENTRY = { path = "/run/secrets/initrd-ssh-host-key-sentry"; owner = "j_kro"; group = "users"; };
  INITRD_SSH_KEY_ZEPHYR = { path = "/run/secrets/initrd-ssh-host-key-zephyr"; owner = "j_kro"; group = "users"; };

  # ── kubernetes (block 2) ────────────────────────────────────
  CASDOOR_MAPLESPIKE_API_CLIENT_SECRET = { path = "/run/secrets/casdoor-maplespike-api-client-secret"; owner = "root"; };
  CASDOOR_MAPLESPIKE_PORTAL_CLIENT_SECRET = { path = "/run/secrets/casdoor-maplespike-portal-client-secret"; owner = "root"; };
  CASDOOR_MAPLESPIKE_MCP_CLIENT_SECRET = { path = "/run/secrets/casdoor-maplespike-mcp-client-secret"; owner = "root"; };
  MISSION_CONTROL_API_KEY = { path = "/run/secrets/mission-control-api-key"; owner = "j_kro"; group = "users"; };
  MISSION_CONTROL_AUTH_PASS = { path = "/run/secrets/mission-control-auth-pass"; owner = "j_kro"; group = "users"; };
  SEARXNG_SECRET_KEY = { path = "/run/secrets/searxng-secret-key"; owner = "root"; };
  SSH_CA_KEY = { path = "/run/secrets/ssh-ca-key"; owner = "j_kro"; group = "users"; };
  SWITCH_ADMIN = { path = "/run/secrets/switch-admin"; owner = "j_kro"; group = "users"; };
  K3S_CLUSTER_TOKEN = { path = "/run/secrets/k3s-cluster-token"; owner = "root"; };

  # ── storage ─────────────────────────────────────────────────
  GARAGE_METRICS_TOKEN = { path = "/run/secrets/garage-metrics-token"; owner = "root"; };
  GARAGE_RPC_SECRET = { path = "/run/secrets/garage-rpc-secret"; owner = "root"; };
  GARAGE_ACCESS_KEY = { path = "/run/secrets/garage-s3-access-key-id"; owner = "j_kro"; group = "users"; };
  GARAGE_SECRET_KEY = { path = "/run/secrets/garage-s3-secret-key"; owner = "root"; };
}

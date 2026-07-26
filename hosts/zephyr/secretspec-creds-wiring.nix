# Zephyr secretspec-creds wiring
# One entry per /run/secrets/ path
{
  # ── aiServices ──────────────────────────────────────────────
  NVIDIA_API_KEY = { path = "/run/secrets/nvidia-api-key"; file = "ai/nvidia-api-key.yaml"; owner = "j_kro"; group = "users"; };
  HUGGINGFACE_TOKEN = { path = "/run/secrets/huggingface-token"; file = "ai/huggingface-token.yaml"; owner = "root"; };
  OPENCODE_ZEN_API_KEY = { path = "/run/secrets/opencode-api-key"; file = "ai/opencode-api-key.yaml"; owner = "j_kro"; group = "users"; };
  OPENCODE_GO_API_KEY = { path = "/run/secrets/opencode-go-api-key"; file = "ai/opencode-go-api-key.yaml"; owner = "j_kro"; group = "users"; };
  CONTEXT7_API_KEY = { path = "/run/secrets/context7-api-key"; file = "ai/context7-api-key.yaml"; owner = "j_kro"; group = "users"; };
  GEMINI_API_KEY = { path = "/run/secrets/gemini-api-key"; file = "ai/gemini-api-key.yaml"; owner = "j_kro"; group = "users"; };
  HERMES_API_SERVER_KEY = { path = "/run/secrets/hermes-api-server-key"; file = "ai/hermes-api-server-key.yaml"; owner = "j_kro"; group = "users"; };
  HERMES_WEBUI_PASSWORD = { path = "/run/secrets/hermes-webui-password"; file = "ai/hermes-webui-password.yaml"; owner = "root"; };
  EXA_API_KEY = { path = "/run/secrets/exa-api-key"; file = "ai/exa-api-key.yaml"; owner = "j_kro"; group = "users"; };
  KATZILLA_API_KEY = { path = "/run/secrets/katzilla-api-key"; file = "ai/katzilla-api-key.yaml"; owner = "j_kro"; group = "users"; };
  KILO_API_KEY = { path = "/run/secrets/kilo-api-key"; file = "ai/kilo-api-key.yaml"; owner = "j_kro"; group = "users"; };
  LOCALMAXXING_API_KEY = { path = "/run/secrets/localmaxxing-api-key"; file = "ai/localmaxxing-api-key.yaml"; owner = "j_kro"; group = "users"; };
  NEOCITIES_API_KEY = { path = "/run/secrets/neocities-api-key"; file = "ai/neocities-api-key.yaml"; owner = "j_kro"; group = "users"; };
  POLLINATIONS_API_KEY = { path = "/run/secrets/pollinations-api-key"; file = "ai/pollinations-api-key.yaml"; owner = "j_kro"; group = "users"; };
  XAI_ACCESS_TOKEN = { path = "/run/secrets/xai-access-token"; file = "ai/xai-access-token.yaml"; owner = "root"; };
  ZAI_API_KEY = { path = "/run/secrets/zai-api-key"; file = "ai/zai-api-key.yaml"; owner = "j_kro"; group = "users"; };
  CACHIX_TOKEN = { path = "/run/secrets/cachix-token"; file = "ai/cachix-token.yaml"; owner = "root"; };

  # ── kubernetes ──────────────────────────────────────────────
  K3S_CLUSTER_TOKEN = { path = "/run/secrets/k3s-cluster-token"; file = "k8s/k3s-cluster-token.yaml"; owner = "root"; };

  # ── ci ───────────────────────────────────────────────────────
  GITHUB_RUNNER_PAT = { path = "/run/secrets/github-runner-pat"; file = "ci/github-runner-pat.yaml"; owner = "j_kro"; group = "users"; };

  # ── infra ──────────────────────────────────────────────────
  CNS_SSH_KEY = { path = "/run/secrets/cns-ssh-key"; file = "infra/cns-ssh-key.yaml"; owner = "j_kro"; group = "users"; };
  SSH_CA_KEY = { path = "/run/secrets/ssh-ca-key"; file = "infra/ssh-ca-key.yaml"; owner = "j_kro"; group = "users"; };
  SWITCH_ADMIN = { path = "/run/secrets/switch-admin"; file = "infra/switch-admin.yaml"; owner = "j_kro"; group = "users"; };
}

# Zephyr secretspec-creds wiring
# One entry per /run/secrets/ path
{
  # ── aiServices ──────────────────────────────────────────────
  EXA_API_KEY = {
    path = "/run/secrets/exa-api-key";
    file = "ai/exa-api-key.yaml";
    key = "exa_api_key";
    owner = "j_kro";
    group = "users";
  };
  NVIDIA_API_KEY = {
    path = "/run/secrets/nvidia-api-key";
    file = "ai/nvidia-api-key.yaml";
    owner = "j_kro";
    group = "users";
  };
  HUGGINGFACE_TOKEN = {
    path = "/run/secrets/huggingface-token";
    file = "ai/huggingface-token.yaml";
    owner = "root";
  };
  OPENCODE_ZEN_API_KEY = {
    path = "/run/secrets/opencode-api-key";
    file = "ai/opencode-api-key.yaml";
    owner = "j_kro";
    group = "users";
  };
  OPENCODE_GO_API_KEY = {
    path = "/run/secrets/opencode-go-api-key";
    file = "ai/opencode-go-api-key.yaml";
    owner = "j_kro";
    group = "users";
  };
  CONTEXT7_API_KEY = {
    path = "/run/secrets/context7-api-key";
    file = "ai/context7-api-key.yaml";
    owner = "j_kro";
    group = "users";
  };

  HERMES_API_SERVER_KEY = {
    path = "/run/secrets/hermes-api-server-key";
    file = "ai/hermes-api-server-key.yaml";
    owner = "j_kro";
    group = "users";
  };
  HERMES_WEBUI_PASSWORD = {
    path = "/run/secrets/hermes-webui-password";
    file = "ai/hermes-webui-password.yaml";
    owner = "root";
  };
  KATZILLA_API_KEY = {
    path = "/run/secrets/katzilla-api-key";
    file = "ai/katzilla-api-key.yaml";
    owner = "j_kro";
    group = "users";
  };
  KILO_API_KEY = {
    path = "/run/secrets/kilo-api-key";
    file = "ai/kilo-api-key.yaml";
    owner = "j_kro";
    group = "users";
  };
  LOCALMAXXING_API_KEY = {
    path = "/run/secrets/localmaxxing-api-key";
    file = "ai/localmaxxing-api-key.yaml";
    owner = "j_kro";
    group = "users";
  };
  NEOCITIES_API_KEY = {
    path = "/run/secrets/neocities-api-key";
    file = "ai/neocities-api-key.yaml";
    owner = "j_kro";
    group = "users";
  };
  POLLINATIONS_API_KEY = {
    path = "/run/secrets/pollinations-api-key";
    file = "ai/pollinations-api-key.yaml";
    owner = "j_kro";
    group = "users";
  };
  XAI_ACCESS_TOKEN = {
    path = "/run/secrets/xai-access-token";
    file = "ai/xai-access-token.yaml";
    owner = "root";
  };
  # ── ZAI_API_KEY removed 2026-07-15 ─────────────────────────────────────────
  # Z.AI is fully gone from the cluster (no MCP servers, no LLM provider, no
  # secrets). The ai-coding-tools.nix module still references it for
  # backwards-compat shell helpers but no longer requires the secret to
  # resolve on disk.
  CACHIX_TOKEN = {
    path = "/run/secrets/cachix-token";
    file = "ai/cachix-token.yaml";
    owner = "root";
  };

  # ── ci ───────────────────────────────────────────────────────
  GITHUB_RUNNER_PAT = {
    path = "/run/secrets/github-runner-pat";
    file = "ci/github-runner-pat.yaml";
    owner = "j_kro";
    group = "users";
  };

  # ── infra ──────────────────────────────────────────────────
  CNS_SSH_KEY = {
    path = "/run/secrets/cns-ssh-key";
    file = "infra/cns-ssh-key.yaml";
    owner = "j_kro";
    group = "users";
  };
  # SSH CA signing key — root-only (0400): the signer service runs as root,
  # and a world-readable CA private key + wildcard @cert-authority trust would
  # let any host compromise mint host certs for the whole fleet.
  SSH_CA_KEY = {
    path = "/run/secrets/ssh-ca-key";
    file = "infra/ssh-ca-key.yaml";
    mode = "0400";
    owner = "root";
    group = "root";
  };
  # GitHub HTTPS credentials — one line `https://...@github.com`, written to
  # j_kro's home so `credential.helper store` (common-host-defaults.nix)
  # serves HTTPS remotes. SSH remotes authenticate via the CA-signed user
  # key (ssh-ca.nix autoSign); this is the HTTPS fallback only.
  GIT_CREDENTIALS = {
    path = "/home/j_kro/.git-credentials";
    file = "infra/git-credentials.yaml";
    mode = "0600";
    owner = "j_kro";
    group = "users";
  };
  SWITCH_ADMIN = {
    path = "/run/secrets/switch-admin";
    file = "infra/switch-admin.yaml";
    owner = "j_kro";
    group = "users";
  };

  # ── storage (garage S3) ────────────────────────────────────
  # backup-to-garage reads these to authenticate to nexus garage
  # (missing on zephyr -> GARAGE_ACCESS_KEY: unbound variable, 2026-08-14).
  GARAGE_ACCESS_KEY = {
    path = "/run/secrets/garage-s3-access-key-id";
    file = "storage/garage-s3-access-key-id.yaml";
    key = "data";
    owner = "root";
    # backup-to-garage wrapper runs as root; the garage system user/group
    # only exists on nexus (garage-cluster.enable). root:root 0440 is enough.
    group = "root";
    mode = "0440";
  };
  GARAGE_SECRET_KEY = {
    path = "/run/secrets/garage-s3-secret-key";
    file = "storage/garage-s3-secret-key.yaml";
    key = "data";
    owner = "root";
    group = "root";
    mode = "0440";
  };
}

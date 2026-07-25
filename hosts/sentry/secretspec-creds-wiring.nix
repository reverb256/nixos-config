{
  K3S_CLUSTER_TOKEN = { path = "/run/secrets/k3s-cluster-token"; file = "k8s/k3s-cluster-token.yaml"; owner = "root"; };
  K3S_ENCRYPTION_KEY = { path = "/run/secrets/k3s-encryption-key"; file = "infra/k3s-encryption-key.json"; owner = "root"; };
  CNS_SSH_KEY = { path = "/run/secrets/cns-ssh-key"; file = "infra/cns-ssh-key.yaml"; owner = "j_kro"; group = "users"; };
  SSH_CA_KEY = { path = "/run/secrets/ssh-ca-key"; file = "infra/ssh-ca-key.yaml"; owner = "j_kro"; group = "users"; };
  SWITCH_ADMIN = { path = "/run/secrets/switch-admin"; file = "infra/switch-admin.yaml"; owner = "j_kro"; group = "users"; };
  GITHUB_RUNNER_PAT = { path = "/run/secrets/github-runner-pat"; file = "ci/github-runner-pat.yaml"; owner = "j_kro"; group = "users"; };
  NVIDIA_API_KEY = { path = "/run/secrets/nvidia-api-key"; file = "ai/nvidia-api-key.yaml"; owner = "j_kro"; group = "users"; };
  OPENCODE_ZEN_API_KEY = { path = "/run/secrets/opencode-api-key"; file = "ai/opencode-api-key.yaml"; owner = "j_kro"; group = "users"; };
  OPENCODE_GO_API_KEY = { path = "/run/secrets/opencode-go-api-key"; file = "ai/opencode-go-api-key.yaml"; owner = "j_kro"; group = "users"; };
  CONTEXT7_API_KEY = { path = "/run/secrets/context7-api-key"; file = "ai/context7-api-key.yaml"; owner = "j_kro"; group = "users"; };
}

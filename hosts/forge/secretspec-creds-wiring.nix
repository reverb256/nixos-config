{
  # kubernetes secrets forge needs (via sops kubernetes flag)
  K3S_CLUSTER_TOKEN = { path = "/run/secrets/k3s-cluster-token"; file = "k8s/k3s-cluster-token.yaml"; owner = "root"; };
  K3S_ENCRYPTION_KEY = { path = "/run/secrets/k3s-encryption-key"; file = "infra/k3s-encryption-key.json"; owner = "root"; };
  CNS_SSH_KEY = { path = "/run/secrets/cns-ssh-key"; file = "infra/cns-ssh-key.yaml"; owner = "j_kro"; group = "users"; };
  # SSH CA signing key — root-only (0400): the signer service runs as root,
  # and a world-readable CA private key + wildcard @cert-authority trust would
  # let any host compromise mint host certs for the whole fleet.
  SSH_CA_KEY = { path = "/run/secrets/ssh-ca-key"; file = "infra/ssh-ca-key.yaml"; mode = "0400"; owner = "root"; group = "root"; };
  SWITCH_ADMIN = { path = "/run/secrets/switch-admin"; file = "infra/switch-admin.yaml"; owner = "j_kro"; group = "users"; };
  FROSTBITE_POSTGRES = { path = "/run/secrets/frostbite-postgres"; file = "k8s/frostbite-postgres.yaml"; owner = "j_kro"; group = "users"; };
  GITEA_RUNNER_TOKEN = { path = "/run/secrets/gitea-runner-token"; file = "ci/gitea-runner-token.yaml"; owner = "root"; };
  GITEA_RUNNER_URL = { path = "/run/secrets/gitea-runner-url"; file = "ci/gitea-runner-url.yaml"; owner = "j_kro"; group = "users"; };
}

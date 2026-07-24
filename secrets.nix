# Agenix secrets configuration
# Maps encrypted files to the public keys that can decrypt them
let
  # User keys - for manual decryption
  users = {
    j_kro = "age1p98yp8w64rdugp03332gxnz5q2vcnucn69cs5qm6s2l2u7epqfcqmu2pqe";
  };
  # Host keys - for automatic decryption at build time
  # Collected: 2025-03-05
  hosts = {
    zephyr = "age1dz76s3x343a5hc2dqyqkufazd96s0ct0jxu3uk6vp2aalpdrffdsgapj4j";
    forge = "age19sjd6ska90xxwyap4xvp83ne9mnkuf667reevmelcqltv0vtxurq3sj55y";
    nexus = "age1v9d4x0r3f500tr73hdp5vseszzkacmrwjw78nfyjke3gq7qsu55qq769pv";
    sentry = "age12dcxvrg4g4c8249mpt89x08hlrylw26xy89maamarjz887z8cvfstx0cf6";
  };
in
{

  # AI SERVICE API KEYS

  # LM Studio API key - Local LLM backend authentication
  #  "lm-studio-api-key.age".publicKeys = [
  #    users.j_kro
  #    hosts.zephyr
  #  ];
  #  "secrets/lm-studio-api-key.age".publicKeys = [
  #    users.j_kro
  #    hosts.zephyr
  #  ];
  # Hugging Face token - Used by AI inference services
  "huggingface-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr
    hosts.nexus
  ];
  "secrets/huggingface-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr
    hosts.nexus
  ];
  # NVIDIA NIM API key - Free LLM endpoints (100+ models)
  "nvidia-api-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
    hosts.nexus
  ];
  "secrets/nvidia-api-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
    hosts.nexus
  ];

  # ZAI API key - ZAI Coding Plan API (needed on all hosts for Hermes + ai-inference)
  "zai-api-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
    hosts.nexus
    hosts.forge
    hosts.sentry
  ];
  "secrets/zai-api-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
    hosts.nexus
    hosts.forge
    hosts.sentry
  ];
  # Pollinations API key - Free AI service (text, image, TTS)
  "pollinations-api-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "secrets/pollinations-api-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  # Kilo API key - Additional AI service
  "kilo-api-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "secrets/kilo-api-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  # Context7 API key - Documentation search service
  "context7-api-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "secrets/context7-api-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  # Gemini API key - Google AI for onetool ground search
  "gemini-api-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  # Exa API key - Web search engine for pi (1,000 searches/month free)
  "exa-api-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "secrets/exa-api-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  # Anthropic API key - Claude API for autoresearch skill optimization
  # "anthropic-api-key.age".publicKeys = [
  #   users.j_kro
  #   hosts.zephyr
  # ];
  # "secrets/anthropic-api-key.age".publicKeys = [
  #   users.j_kro
  #   hosts.zephyr
  # ];
  # Spacebot Telegram token - AI agent Telegram integration
  "spacebot-telegram-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "secrets/spacebot-telegram-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];

  # INFRASTRUCTURE SECRETS

  # Switch admin password - Network switch management
  "switch-admin.age".publicKeys = [ users.j_kro ];
  "secrets/switch-admin.age".publicKeys = [ users.j_kro ];

  # MONITORING SECRETS

  # Grafana admin password - Monitoring dashboard access
  "grafana-admin.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "secrets/grafana-admin.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];

  # NEXTCLOUD SECRETS

  # Nextcloud admin password
  "nextcloud-admin.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "secrets/nextcloud-admin.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];

  # VAULTWARDEN SECRETS

  # Vaultwarden admin token - Admin panel access
  "vaultwarden-admin-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "secrets/vaultwarden-admin-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];

  # MINING SECRETS

  # Required on all Ryzen nodes (zephyr, nexus, sentry) for build detection
    users.j_kro
    hosts.zephyr
    hosts.nexus
    hosts.sentry
  ];
    users.j_kro
    hosts.zephyr
    hosts.nexus
    hosts.sentry
  ];
    users.j_kro
    hosts.zephyr
  ];
    users.j_kro
    hosts.zephyr
  ];
    users.j_kro
    hosts.zephyr
  ];
    users.j_kro
    hosts.zephyr
  ];
  # Tailscale API key - Tailscale service authentication
  "tailscale-api-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "secrets/tailscale-api-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];

  # GARAGE S3 STORAGE SECRETS

  # Garage RPC secret - Cluster authentication for distributed S3 storage
  "garage-rpc-secret.age".publicKeys = [
    users.j_kro
    hosts.zephyr
    hosts.nexus
    hosts.sentry
  ];
  "secrets/garage-rpc-secret.age".publicKeys = [
    users.j_kro
    hosts.zephyr
    hosts.nexus
    hosts.sentry
  ];
  # Garage S3 admin secret key - For automated backups to S3
  "garage-s3-secret-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "secrets/garage-s3-secret-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];

  # CLOUDFLARE TUNNEL SECRETS

  # Cloudflare Tunnel credentials
  # Token contains: AccountID, TunnelID, TunnelSecret
  "cloudflared-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr # Primary node running cloudflared
  ];
  "secrets/cloudflared-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr # Primary node running cloudflared
  ];
  # Cloudflare API token - DNS and cache operations
  # Token contains: API token for Zone:DNS:Edit, Zone:Read, Zone:Cache:Purge
  "secrets/cloudflare-api-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];

  # GITHUB CONTAINER REGISTRY TOKENS

  # GitHub Container Registry (GHCR) token - For pushing Docker images
  "github-ghcr-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "secrets/github-ghcr-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];

  # K3S CLUSTER SECRETS

  # k3s cluster token - used for server/agent authentication
  "k3s-cluster-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr
    hosts.nexus
    hosts.sentry
    hosts.forge
  ];
  "secrets/k3s-cluster-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr
    hosts.nexus
    hosts.sentry
    hosts.forge
  ];

  # KUBERNETES HA ETCD CERTIFICATES (DEPRECATED - kept for rollback)

  # CA certificate and key
  "kubernetes-ca.age".publicKeys = [
    users.j_kro
    hosts.zephyr
    hosts.nexus
    hosts.sentry
  ];
  # API server key (shared by all masters)
  "apiserver-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
    hosts.nexus
    hosts.sentry
  ];
  "secrets/apiserver-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
    hosts.nexus
    hosts.sentry
  ];
  # etcd peer key (shared by all etcd members)
  "etcd-peer-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
    hosts.nexus
    hosts.sentry
  ];
  "secrets/etcd-peer-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
    hosts.nexus
    hosts.sentry
  ];
  # Per-node etcd server keys
  "etcd-zephyr-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "secrets/etcd-zephyr-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "etcd-nexus-key.age".publicKeys = [
    users.j_kro
    hosts.nexus
  ];
  "secrets/etcd-nexus-key.age".publicKeys = [
    users.j_kro
    hosts.nexus
  ];
  "etcd-sentry-key.age".publicKeys = [
    users.j_kro
    hosts.sentry
  ];
  "secrets/etcd-sentry-key.age".publicKeys = [
    users.j_kro
    hosts.sentry
  ];
}

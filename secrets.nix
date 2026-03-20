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
in {
  # ========================================================================
  # AI SERVICE API KEYS
  # ========================================================================

  # Hugging Face token - Used by AI inference services
  "huggingface-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "secrets/huggingface-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];

  # LM Studio API key - Local AI model API
  "lm-studio-api-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "secrets/lm-studio-api-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];

  # ZAI API key - ZAI Coding Plan API
  "zai-api-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "secrets/zai-api-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
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

  # Spacebot Telegram token - AI agent Telegram integration
  "spacebot-telegram-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "secrets/spacebot-telegram-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];

  # ========================================================================
  # INFRASTRUCTURE SECRETS
  # ========================================================================

  # Switch admin password - Network switch management
  "switch-admin.age".publicKeys = [users.j_kro];
  "secrets/switch-admin.age".publicKeys = [users.j_kro];

  # ========================================================================
  # MONITORING SECRETS
  # ========================================================================

  # Grafana admin password - Monitoring dashboard access
  "grafana-admin.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "secrets/grafana-admin.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];

  # Sentry DSN - Error tracking for AI inference gateway
  "sentry-dsn.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "secrets/sentry-dsn.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];

  # ========================================================================
  # GLITCHTIP SECRETS
  # ========================================================================

  # GlitchTip database password
  "glitchtip-db-password.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "secrets/glitchtip-db-password.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];

  # GlitchTip Django secret key
  "glitchtip-secret-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "secrets/glitchtip-secret-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];

  # ========================================================================
  # NEXTCLOUD SECRETS
  # ========================================================================

  # Nextcloud admin password
  "nextcloud-admin.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "secrets/nextcloud-admin.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];

  # ========================================================================
  # VAULTWARDEN SECRETS
  # ========================================================================

  # Vaultwarden admin token - Admin panel access
  "vaultwarden-admin-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "secrets/vaultwarden-admin-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];

  # ========================================================================
  # MINING SECRETS
  # ========================================================================

  # XMRig HTTP API token - Used to pause/resume mining during builds
  # Required on all Ryzen nodes (zephyr, nexus, sentry) for build detection
  "xmrig-api-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr
    hosts.nexus
    hosts.sentry
  ];
  "secrets/xmrig-api-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr
    hosts.nexus
    hosts.sentry
  ];

  # XMRig always-on instance API token - Dual XMRig architecture
  "xmrig-always-api-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "secrets/xmrig-always-api-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];

  # XMRig flexible (pause-able) instance API token - Dual XMRig architecture
  "xmrig-flexible-api-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];
  "secrets/xmrig-flexible-api-token.age".publicKeys = [
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

  # ========================================================================
  # GARAGE S3 STORAGE SECRETS
  # ========================================================================

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

  # ========================================================================
  # AKASH PROVIDER SECRETS
  # ========================================================================

  # Akash provider wallet key - For earning AKT/USDC from GPU compute
  "akash-provider-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr # Control plane node - primary provider
    # Add other hosts if running provider on multiple nodes:
    # hosts.forge
    # hosts.nexus
    # hosts.sentry
  ];
  "secrets/akash-provider-key.age".publicKeys = [
    users.j_kro
    hosts.zephyr
  ];

  # ========================================================================
  # CLOUDFLARE TUNNEL SECRETS
  # ========================================================================

  # Cloudflare Tunnel credentials - For Akash provider public ingress
  # Token contains: AccountID, TunnelID, TunnelSecret
  "cloudflared-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr # Primary node running cloudflared
  ];
  "secrets/cloudflared-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr # Primary node running cloudflared
  ];

  # Cloudflare API token - DNS and cache operations for Akash provider
  # Token contains: API token for Zone:DNS:Edit, Zone:Read, Zone:Cache:Purge
  "secrets/cloudflare-api-token.age".publicKeys = [
    users.j_kro
    hosts.zephyr # Primary node running Akash Cloudflare integration
  ];
}

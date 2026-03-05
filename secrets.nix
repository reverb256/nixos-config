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
  # ========================================================================
  # AI SERVICE API KEYS
  # ========================================================================

  # Hugging Face token - Used by AI inference services
  "huggingface-token.age".publicKeys = [ users.j_kro hosts.zephyr ];
  "secrets/huggingface-token.age".publicKeys = [ users.j_kro hosts.zephyr ];

  # LM Studio API key - Local AI model API
  "lm-studio-api-key.age".publicKeys = [ users.j_kro hosts.zephyr ];
  "secrets/lm-studio-api-key.age".publicKeys = [ users.j_kro hosts.zephyr ];

  # ZAI API key - ZAI Coding Plan API
  "zai-api-key.age".publicKeys = [ users.j_kro hosts.zephyr ];
  "secrets/zai-api-key.age".publicKeys = [ users.j_kro hosts.zephyr ];

  # Kilo API key - Additional AI service
  "kilo-api-key.age".publicKeys = [ users.j_kro hosts.zephyr ];
  "secrets/kilo-api-key.age".publicKeys = [ users.j_kro hosts.zephyr ];

  # ========================================================================
  # INFRASTRUCTURE SECRETS
  # ========================================================================

  # Switch admin password - Network switch management
  "switch-admin.age".publicKeys = [ users.j_kro ];
  "secrets/switch-admin.age".publicKeys = [ users.j_kro ];
}

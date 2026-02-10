# Mining Service Configuration Module
# Extracted from configuration.nix - Centralized mining service setup
_: {
  # Mining service configuration
  services.mining = {
    enable = true;
    xmrig = {
      enable = true;
      pool = "stratum+ssl://xtm-rx-us.kryptex.network:8038"; # Kryptex XTM RX pool
      threads = 18; # System service (full mode): 18 threads
      # SECURITY FIX: Token loaded from agenix secrets
      httpToken = builtins.readFile "/run/agenix/mining-api-token";
    };
    lolminer = {
      enable = true;
      nvidia.enable = true; # NVIDIA GPU mining
      nvidia.devices = "0"; # GPU device
      nvidia.powerLimit = 250; # Power limit
      nvidia.apiPort = 4068; # API port
      algorithm = "CR29"; # Mining algorithm
      pool = "stratum+ssl://xtm-c29-us.kryptex.network:8040"; # Correct pool
      # Wallet auto-derived from hostname: krxXVNVMM7.{hostname}
    };
  };
}

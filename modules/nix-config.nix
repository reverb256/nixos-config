# Nix Module
# Extracted from configuration.nix - Nix configuration and optimization
{...}: {
  # ============================================================================
  # NIX CONFIGURATION - Experimental features, build optimization, and caching
  # ============================================================================
  nix = {
    settings = {
      # Enable experimental Nix features
      experimental-features = ["nix-command" "flakes"];

      # GitHub API authentication to avoid rate limits
      # GitHub API authentication (handled via git credential helper or gh)

      # Allow j_kro to use restricted settings like builders-use-substitutes
      trusted-users = ["root" "j_kro"];

      # Phase 1: CPU governor for gaming performance
      max-jobs = 8; # Parallel derivations (use ~1/2 of threads)
      cores = 16; # Cores per derivation (use ~1/2 of cores)

      # Distributed build configuration temporarily disabled to resolve cache issues
      # builders-use-substitutes = true;

      # 5-tier binary caching + CUDA cache
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://ezkea.cachix.org"
        "https://nixpkgs-wayland.cachix.org"
        "https://nix-gaming.cachix.org"
        "https://cuda-maintainers.cachix.org"
        "https://reverb-os:0Pia23Zz0TnAP3m4ZSYzpFQkc6icPUpl+Is/AFeqofY="
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
        "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
        "nix-gaming.cachix.org-1:vn/szNT7r/Pc1FbcBjRGHLk7XNk0v2KvMq2v7EwXQ8w="
        "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
        "reverb-os:0Pia23Zz0TnAP3m4ZSYzpFQkc6icPUpl+Is/AFeqofY="
      ];
      # Sign packages we build for distributed deployment
      secret-key-files = "/etc/nixos/secrets/nix-cache-key.sec";
    };
  };
}

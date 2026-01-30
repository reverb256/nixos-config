# Nix Module
# Extracted from configuration.nix - Nix configuration and optimization
{config, ...}: {
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

      # Binary caches for faster builds (ordered by priority)
      # Documentation: AGENTS.md#binary-caches
      substituters = [
        # Official NixOS cache (primary)
        "https://cache.nixos.org"
        # CUDA packages (PyTorch, TensorFlow, etc.)
        "https://cuda-maintainers.cachix.org"
        # Nix-community packages (various tools)
        "https://nix-community.cachix.org"
        # Wayland packages (Hyprland, sway, etc.)
        "https://nixpkgs-wayland.cachix.org"
        # Gaming packages (Proton-GE, GameMode, etc.)
        "https://nix-gaming.cachix.org"
        # Anime Games Launcher (AAGL)
        "https://ezkea.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
        "nix-gaming.cachix.org-1:vn/szNT7r/Pc1FbcBjRGHLk7XNk0v2KvMq2v7EwXQ8w="
        "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
      ];
    };
  };
}

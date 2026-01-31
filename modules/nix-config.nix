# Nix Module
# Extracted from configuration.nix - Nix configuration and optimization
{config, ...}: {
  # ============================================================================
  # NIX CONFIGURATION - Experimental features, build optimization, and caching
  # ============================================================================
  nix = {
    settings = {
       # GitHub API authentication (handled via git credential helper or gh)

       # Fix for 'input-addressed derivations' error
       # Enable CA derivations and allow local building
       experimental-features = ["nix-command" "flakes" "ca-derivations"];

      # Build resource management - avoid oversubscription
      # Zephyr has 32 cores (16 physical + 16 hyperthread)
      # Formula: max-jobs * cores = total cores used
      # Setting: 4 jobs * 6 cores = 24 cores used, leaving 8 for desktop/mining
      max-jobs = lib.mkDefault 4; # Parallel derivations (conservative for desktop use, overridable by distributed-builds)
      cores = 6; # Cores per derivation (leaves headroom for gaming/mining)

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
        # Zen Browser - Pre-built binaries (NO MORE COMPILATION!)
        "https://zen-browser.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
        "nix-gaming.cachix.org-1:vn/szNT7r/Pc1FbcBjRGHLk7XNk0v2KvMq2v7EwXQ8w="
        "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
        "zen-browser.cachix.org-1:z/QLGrEkiBYF/7zoHX1Hpuv0B26QrmbVBSy9yDD2tSs="
      ];
    };
  };
}

# Nix Module
# Extracted from configuration.nix - Nix configuration and optimization
{lib, ...}: {
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

      # Binary caches for faster builds (ALL FREE - $0 to download)
      # Ordered by priority: official > CUDA > community > specialized
      substituters = [
        # Official NixOS cache (primary)
        "https://cache.nixos.org"
        # CUDA packages (PyTorch, TensorFlow, LM Studio, etc.)
        "https://cache.nixos-cuda.org"
        # Nix-community packages (various tools)
        "https://nix-community.cachix.org"
        # Wayland packages (Hyprland, sway, etc.)
        "https://nixpkgs-wayland.cachix.org"
        # Gaming packages (Proton-GE, GameMode, etc.)
        "https://nix-gaming.cachix.org"
        # Anime Games Launcher (AAGL)
        "https://ezkea.cachix.org"
        # Zen Browser - Pre-built binaries
        "https://zen-browser.cachix.org"
        # Devenv - Development environment packages
        "https://devenv.cachix.org"
        # Garnix - CI/CD builds (free for open source)
        "https://cache.garnix.io"
        # Reverb OS - Your personal Cachix cache
        "https://reverb-os.cachix.org"
      ];

      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nixpkgs-wayland.cachix.org-1:3lwxaILxMRkVhehr5StQprHdEo4IrE8sRho9R9HOLYA="
        "nix-gaming.cachix.org-1:vn/szNT7r/Pc1FbcBjRGHLk7XNk0v2KvMq2v7EwXQ8w="
        "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
        "zen-browser.cachix.org-1:z/QLGrEkiBYF/7zoHX1Hpuv0B26QrmbVBSy9yDD2tSs="
        "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
        "reverb-os.cachix.org-1:dctKtu02bV/4fbsYbGuVVxQo9R7X6lNqUet1qj2jYz="
        # "magic.nixos.org-1:eRQ8mF8J9FqT6yV6k3kHdYiVr4R9mYr2A="
      ];

      # TEMPORARY: Disable signature checks to fix NVIDIA driver issues
      require-sigs = false;
    };
  };
}

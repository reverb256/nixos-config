# Nix Configuration Module
# Binary caches, experimental features, and Nix settings
{lib, ...}: {
  # Enable nix-command and flakes
  nix.settings = {
    experimental-features = ["nix-command" "flakes"];

    # Binary caches
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
      "https://cache.nixos-cuda.org"
      "https://ezkea.cachix.org"
    ];

    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
      "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
    ];

    trusted-users = ["root" "@wheel"];

    # Allow unsigned paths for local cluster deployment
    # This enables colmena to deploy between hosts without requiring signature setup
    require-sigs = false;

    # Accept substituters from all cluster hosts
    # (Host keys are added via dynamic discovery)
    accept-flake-config = true;
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # ============================================================================
  # STORAGE OPTIMIZATION (from XNM1)
  # ============================================================================
  # Automatic store optimization and garbage collection
  # Manual commands:
  #   nix-store --optimize       # Eliminate redundant copies
  #   nix-store --gc             # Remove unreferenced paths
  #   nix-collect-garbage -d     # Delete old generations
  nix.settings.auto-optimise-store = true;
  nix.optimise.automatic = true;
  nix.optimise.dates = "weekly";

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = lib.mkForce "--delete-older-than 14d";  # Override distributed-builds (30d)
  };
}

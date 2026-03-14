# Nix Configuration Module
# Binary caches, experimental features, and Nix settings
{lib, ...}: {
  nix = {
    # Enable nix-command and flakes
    settings = {
      experimental-features = ["nix-command" "flakes"];

      # Binary caches (local cache checked first)
      # Harmonia runs on port 5000 (not 50000 - that was old nix-serve)
      # Use cluster IP address instead of Tailscale hostname for DNS reliability
      # Use mkBefore to ensure local cache is first before other modules' substituters
      # Public caches are now in distributed-builds.nix (to reduce duplication)
      substituters = lib.mkBefore [
        "http://10.1.1.110:5000?trusted=1"
      ];

      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
        "nexus-cache:qR+dIToYHrN3iJlg2puMRM8zrMtgZ4H7cISSR9E0iEE="
      ];

      trusted-users = ["root" "@wheel"];

      # Allow unsigned paths for local cluster deployment
      # This enables colmena to deploy between hosts without requiring signature setup
      require-sigs = false;

      # Accept substituters from all cluster hosts
      # (Host keys are added via dynamic discovery)
      accept-flake-config = true;

      # STORAGE OPTIMIZATION (from XNM1)
      # Automatic store optimization
      auto-optimise-store = true;
    };

    # Automatic garbage collection
    gc = {
      automatic = true;
      dates = "weekly";
      options = lib.mkForce "--delete-older-than 14d"; # Override distributed-builds (30d)
    };

    # Store size limits (prevents disk exhaustion)
    settings.max-free = lib.mkDefault "100G"; # Keep ~100GB free
    settings.min-free = lib.mkDefault "5G"; # Keep at least 5GB free

    # Automatic store optimization
    optimise = {
      automatic = true;
      dates = "weekly";
    };
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
}

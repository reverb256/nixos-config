# Nix Configuration Module
# Binary caches, experimental features, and Nix settings
{
  lib,
  ...
}: {
  # OVERLAY: Fix cuda_compat issue (Jetson/ARM64-only, breaks x86_64 builds)
  # cuda_cudart has cuda_compat as propagatedBuildInput which fails on x86_64
  # We provide a dummy cuda_compat package and override propagatedBuildInputs
  nixpkgs.overlays = [
    (_final: prev: {
      # Create dummy cuda_compat for x86_64 (Jetson-only package has no source)
      cuda_compat =
        prev.runCommand "cuda_compat-dummy"
        {}
        ''
          mkdir -p $out
          # Dummy package - cuda_compat is only needed for Jetson (aarch64)
            # On x86_64, regular CUDA drivers work fine without it
        '';

      # Apply fix to cudaPackages_12_4 (which we use in gpu-compute.nix)
      cudaPackages_12_4 =
        prev.cudaPackages_12_4
        // {
          cuda_cudart =
            prev.cudaPackages_12_4.cuda_cudart.overrideAttrs
            (old: {
              # Remove cuda_compat from propagatedBuildInputs
              # cuda_compat is Jetson-only (aarch64) and fails on x86_64
              propagatedBuildInputs =
                lib.filter
                (pkg: pkg.pname or "" != "cuda_compat")
                (old.propagatedBuildInputs or []);
              # Also remove any setup hooks that reference cuda-compat
              setupHooks =
                lib.filter
                (hook: !lib.hasInfix "cuda-compat" hook)
                (old.setupHooks or []);
            });
        };
    })
  ];

  nix = {
    # Enable nix-command and flakes
    settings = {
      experimental-features = ["nix-command" "flakes"];

      # Substituters and trusted keys are now configured in distributed-builds.nix
      # to avoid duplication and ensure proper merge order

      trusted-public-keys = lib.mkOptionDefault [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
        # CUDA binary cache - provides prebuilt CUDA packages
        "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
      ];

      trusted-users = lib.mkOptionDefault ["root" "@wheel"];

      # Allow unsigned paths for local cluster deployment
      # This enables colmena to deploy between hosts without requiring signature setup
      require-sigs = lib.mkForce false;

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

  # EXCLUDE cuda_compat (Jetson-only, ARM64, blocks CUDA on x86_64)
  # cuda_compat is pulled in transitively by cuda_cudart → Steam/NVIDIA drivers
  # It's unfree (CUDA EULA) and completely unnecessary on x86_64 systems
  # Explicitly exclude it to prevent build failures and reduce closure size
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "cuda_compat"
      "cuda_compat_12_6"
      "cuda_compat_12_8"
    ]
    -> false;

  # Compiler cache for faster rebuilds
  programs.ccache = {
    enable = true;
    cacheDir = "/var/cache/ccache";
  };
}

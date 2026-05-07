{lib, ...}: {
  nixpkgs.overlays = [
    (_final: prev: {
      cuda_compat =
        prev.runCommand "cuda_compat-dummy"
        {}
        ''
          mkdir -p $out
        '';

      cudaPackages_12_4 =
        prev.cudaPackages_12_4
        // {
          cuda_cudart =
            prev.cudaPackages_12_4.cuda_cudart.overrideAttrs
            (old: {
              propagatedBuildInputs =
                lib.filter
                (pkg: pkg.pname or "" != "cuda_compat")
                (old.propagatedBuildInputs or []);
              setupHooks =
                lib.filter
                (hook: !lib.hasInfix "cuda-compat" hook)
                (old.setupHooks or []);
            });
        };
    })
  ];

  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];

      trusted-public-keys = lib.mkOptionDefault [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
      ];

      trusted-users = lib.mkOptionDefault ["root" "@wheel"];

      require-sigs = lib.mkForce false;

      accept-flake-config = true;

      auto-optimise-store = true;
    };

    gc = {
      automatic = true;
      dates = "weekly";
      options = lib.mkForce "--delete-older-than 14d";
    };

    settings.max-free = lib.mkDefault "100G";
    settings.min-free = lib.mkDefault "5G";

    optimise = {
      automatic = true;
      dates = "weekly";
    };
  };

  nixpkgs.config.allowUnfree = true;

  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "cuda_compat"
      "cuda_compat_12_6"
      "cuda_compat_12_8"
    ]
    -> false;

  programs.ccache = {
    enable = true;
    cacheDir = "/var/cache/ccache";
  };
}

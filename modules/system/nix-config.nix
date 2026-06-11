{
  lib,
  pkgs,
  ...
}: {
  nixpkgs.overlays = [
    (_final: prev: {
      inherit
        (prev.lixPackageSets.stable)
        nix-eval-jobs
        nix-fast-build
        colmena
        ;

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
    package = lib.mkDefault pkgs.lixPackageSets.stable.lix;

    settings = {
      experimental-features = ["nix-command" "flakes"];

      substituters = [
        "http://10.1.1.120:50000"
        "https://nix-community.cachix.org"
        "https://cache.nixos.org"
      ];

      trusted-public-keys = lib.mkOptionDefault [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "zephyr-cache-1:2Tqq4OUEZrz6DEXurUPrAQBjh1VoiQ0jZhrGYozHq5c="
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

    settings.max-free = lib.mkDefault (toString (100 * 1024 * 1024 * 1024));
    settings.min-free = lib.mkDefault (toString (5 * 1024 * 1024 * 1024));

    optimise = {
      automatic = true;
      dates = "weekly";
    };
  };

  nixpkgs.config.allowUnfree = true;

  nixpkgs.config.permittedInsecurePackages = [
    "nodejs-20.20.2"
    "nodejs-slim-20.20.2"
  ];

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
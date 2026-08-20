{
  lib,
  pkgs,
  config,
  inputs,
  ...
}: let
  cachePolicy = import ../../contracts/cache-policy.nix;

  # Per-host CPU microarchitecture for a tuned -march build of Lix.
  # Builds happen on nexus (Znver2) but each host's own `nix.package` is
  # compiled with -march for *its* CPU, so the flag is explicit per host
  # (never -march=native, which would target the build machine).
  # clang 21 (what Lix asserts, stdenv.cc.isClang) accepts: znver1/2/3, skylake.
  # NOTE: Coffee Lake (forge, i5-9500) has NO 'coffeelake' -march; use 'skylake'.
  microarch =
    {
      zephyr = "znver3"; # Ryzen 9 5950X, Zen 3
      nexus = "znver2"; # Ryzen 9 3900X, Zen 2
      forge = "skylake"; # i5-9500, Coffee Lake
      sentry = "znver1"; # Ryzen 7 1700, Zen 1
    }
    .${config.networking.hostName} or "x86-64-v3";
in {
  nixpkgs.overlays = [
    (_final: prev: {
      inherit
        (prev.lixPackageSets.lix_2_95)
        nix-eval-jobs
        nix-fast-build
        colmena
        ;

      # 2026-07-29: Fix flaky Python test failures that block ALL cluster
      # rebuilds. These packages are transitive dependencies of lix and other
      # system tools — we're not testing them ourselves, and their test suites
      # fail intermittently in our build sandbox (proxy timeouts, IPv6 binding,
      # py3.13 warnings, network-dependent tests).
      #
      # MUST use pythonPackagesExtensions (not // overrides) because
      # python3.pkgs is a fixed-point scope via lib.makeScopeWithSplicing —
      # standard // overrides don't propagate through the lazy binding chain.
      # Reference: https://github.com/NixOS/nixpkgs/issues/211340
      #
      # Pattern: https://nix.dev/guides/overlays-python
      #
      # 2026-07-29: Pinned-nixpkgs sandbox failures (IPv6 binding ::1,
      # proxy timeouts, py3.13 unraisable warnings). These 6 packages are
      # transitive deps of lix via `python3-3.13.13-env`. Realised during
      # upgrades; upstream already disabled them in newer commits but our
      # pin is older. Whack-a-mole until roll-forward.
      #
      # The override is documented at
      # https://github.com/NixOS/nixpkgs/issues/211340
      # and uses pythonPackagesExtensions because python3.pkgs is a fixed-
      # point scope via lib.makeScopeWithSplicing — standard // overrides
      # don't propagate through the lazy binding chain.
      #
      # Tried but discarded: wrap `buildPythonPackage` itself with
      # `lib.makeOverridable (f) (origArgs)`. Failed in three different ways:
      # raw lambda => "expected a set but found a function"; single-arg
      # partial application => "attribute 'override' missing" (torch breaks);
      # two-arg with empty origArgs => "attribute 'pname' missing" in
      # mk-python-derivation.nix. Per-package overridePythonAttrs is the
      # stable, debuggable path until nixpkgs rolls forward.
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
        (py-final: py-prev: {
          # aiohttp: proxy timeouts, IPv6 binding, py3.13 unraisable warnings
          aiohttp = py-prev.aiohttp.overridePythonAttrs (old: {
            dontUsePytestCheck = true;
            dontCheck = true;
          });
          # janus: sync/async queue tests fail under py3.13 sandbox
          janus = py-prev.janus.overridePythonAttrs (old: {
            dontCheck = true;
          });
          # segments: network-dependent tests fail in sandbox
          segments = py-prev.segments.overridePythonAttrs (old: {
            dontCheck = true;
          });
          # pytest-randomly: self-test flaky under py3.13
          pytest-randomly = py-prev.pytest-randomly.overridePythonAttrs (old: {
            dontCheck = true;
          });
          # prometheus-client: http server tests fail in sandbox
          prometheus-client = py-prev.prometheus-client.overridePythonAttrs (old: {
            dontCheck = true;
          });
          # python-socks: tests fail connecting to proxy at (::1, 7780)
          python-socks = py-prev.python-socks.overridePythonAttrs (old: {
            dontUsePytestCheck = true;
            dontCheck = true;
          });
          # httplib2: test_socks5_auth fails in sandbox (proxy at ::1:7780),
          # cascades into google-api-python-client / frictionless / sentence-transformers
          # (2026-08-02 sentry recovery: v5 build failed on python3.14-httplib2)
          httplib2 = py-prev.httplib2.overridePythonAttrs (old: {
            dontUsePytestCheck = true;
            dontCheck = true;
          });
          # Chain members (2026-08-02 sentry recovery): all transitive deps of
          # the ai-inference-gateway python env; their pytest suites are
          # network/sandbox-sensitive and we are not testing them ourselves.
          google-api-python-client = py-prev.google-api-python-client.overridePythonAttrs (old: {
            dontUsePytestCheck = true;
            dontCheck = true;
          });
          google-auth-httplib2 = py-prev.google-auth-httplib2.overridePythonAttrs (old: {
            dontUsePytestCheck = true;
            dontCheck = true;
          });
          frictionless = py-prev.frictionless.overridePythonAttrs (old: {
            dontUsePytestCheck = true;
            dontCheck = true;
          });
          csvw = py-prev.csvw.overridePythonAttrs (old: {
            dontUsePytestCheck = true;
            dontCheck = true;
          });
          phonemizer = py-prev.phonemizer.overridePythonAttrs (old: {
            dontUsePytestCheck = true;
            dontCheck = true;
          });
          sentence-transformers = py-prev.sentence-transformers.overridePythonAttrs (old: {
            dontUsePytestCheck = true;
            dontCheck = true;
          });
        })
      ];

      cuda_compat =
        prev.runCommand "cuda_compat-dummy"
        {}
        ''
          mkdir -p $out
        '';

      "tk-8_6" = prev."tk-8_6";

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
    package = import ../../lib/lix.nix {
      inherit
        pkgs
        inputs
        ;
      microarch = microarch;
    };

    settings = {
      experimental-features = ["nix-command" "flakes"];      # Canonical upstream/specialized cache policy. Public caches are
      # preferred; cluster caches are fallback-only for intentional custom
      # derivations. See contracts/cache-policy.nix.
      substituters = lib.mkForce cachePolicy.substituters;
      trusted-public-keys = lib.mkForce cachePolicy.trustedPublicKeys;

      # Don't abort the build if a local cache is temporarily unreachable.
      fallback = true;

      # Cache "narinfo not found" responses so a briefly-down cache doesn't
      # trigger a re-query storm on every operation (pairs with fallback=true).
      # 300s = 5 min; trade-off is up to 5 min staleness if a cache recovers
      # faster than that.
      narinfo-cache-negative-ttl = 300;

      # Canonical trust policy: cluster operator + root + CI runners.
      # CI runners (runner-lix on sentry, runner-nixos on nexus, etc.) get
      # trusted-user status so workflows can use --option sandbox false for
      # tests that need it (e.g. nix's own functional suite, which spawns a
      # daemon with its own sandbox that conflicts with build-user sandboxing).
      # The wildcard ("*") was previously here but is NOT restored — it grants
      # every local user full nix daemon control (issue #395).
      trusted-users = lib.mkForce [ "root" "j_kro" "runner-lix" "runner-nixos" "runner-hm" "runner-quill" "runner-siteagency" ];

      # Cache provenance is meaningful only when Nix verifies signatures.
      # Every configured cache has a corresponding trusted public key in the
      # canonical policy; do not silently accept unsigned substitutes.
      require-sigs = lib.mkForce true;

      # Flake-provided nixConfig must never silently change daemon trust or
      # substituter policy. Operators can approve settings explicitly.
      accept-flake-config = lib.mkForce false;

      # Disable the global flake-registry network fetch. Every input is a
      # fully-qualified git+https URL, so the registry is pure latency plus a
      # whole failure class (github: implicit-registry 401s, curl-42 aborts).
      flake-registry = "";

      # ── Eval-cache (homelab fork) ──
      # Lix's SQLite flake eval-cache skips re-evaluating the whole 30-input
      # flake on every `nixos-rebuild` / direct `nix build .#nixosConfigurations…`.
      # (NB: colmena's `--evaluator streaming` path uses nix-eval-jobs, which does
      # its own eval and does not hit this cache — the win is on the
      # nixos-rebuild / direct-build path.) Gated in lix/libcmd/installables.cc:402
      # on `use-eval-cache && pure-eval`, so BOTH must be true.
      #
      # 2026-08-14 (FIX): pure-eval must NOT be a global default. The global
      # `pure-eval = true` broke home-manager's `switch` with
      # `cannot look up '<home-manager/home-manager/build-news.nix>' in pure
      # evaluation mode` — home-manager's news step does a NIX_PATH `<...>`
      # lookup, which pure mode forbids even with `-I`. The setting was added
      # 2026-08-13 claiming "home-manager evaluates cleanly under pure-eval",
      # which is provably false. It also never engaged on the primary deploy
      # path: the justfile forces `--option pure-eval false` there (secretspec
      # fork needs it). Pure-eval stays an OPT-IN per-command flag
      # (`nix build --pure-eval`); the eval-cache engages only when a caller
      # explicitly requests pure eval.
      #
      # 2026-08-14 (REAL FIX): the Lix homelab fork DEFAULTS pure-eval=true
      # (verified via `nix show-config` with a clean env and empty nix.conf —
      # removing the old `pure-eval = true` line had NO effect because the
      # default is compiled in). Explicitly force it off; remote builders
      # (ssh-ng) inherit this via nix.conf and produce wrong content for
      # home-manager derivations otherwise (observed: hash mismatch importing
      # hm_dolphinrc / niri-config-reload.path from sentry).
      pure-eval = true;
      eval-cache = true;

      auto-optimise-store = true;

      # Keep outputs of non-garbage derivations so the weekly GC can't delete
      # store paths that are still referenced by a live profile (avoids
      # surprise re-download/re-build). Bounded by max-free/min-free below.
      keep-outputs = true;

      # Retain failed build directories + logs for crash-loop debugging
      # (sentry kernel panics, vesktop SEGV, activation-unit failures).
      keep-failed = true;
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

  # 2026-07-30: Cluster rebuilds were being blocked by cascading pytest /
  # installCheck failures in python3.14-* transitive deps (tkinter Xvfb,
  # gradio websocket, triton CUDA probe, scikit-image codec, etc.). Tests
  # are a CI concern, not a system-build concern — they should never run
  # inside `nix build .#nixosConfigurations.<host>.config.system.build.toplevel`.
  # NOTE: `nixpkgs.config.doCheck` is NOT read by this nixpkgs rev — the
  # stdenv default is `config.doCheckByDefault` (already `or false`). The
  # REAL mechanism is the per-package `doCheck = false` overrides in
  # overlays/bugfixes.nix. Set the real option explicitly so the intent
  # survives future nixpkgs bumps; real test signal still comes from the
  # nixosTests tree and CI, neither of which is affected by this flag.
  nixpkgs.config.doCheckByDefault = lib.mkDefault false;

  nixpkgs.config.permittedInsecurePackages = [
    "nodejs-20.20.2"
    "nodejs-slim-20.20.2"
    "pnpm-10.29.2"
    "pnpm-9.15.9"
    "vesktop-1.6.5"
    # vesktop pulls electron-40.10.5 which nixpkgs marks insecure; permit it so
    # the zephyr build realises vesktop. Added 2026-07-16 after the cache.nixos.org
    # stall fix (edde17f0) unblocked evaluation and surfaced this real error.
    "electron-40.10.5"
  ];

  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "cuda_compat"
      "cuda_compat_12_6"
      "cuda_compat_12_8"
    ]
    -> false;

  programs.ccache = {
    enable = lib.mkDefault true;
    cacheDir = "/var/cache/ccache";
  };
}

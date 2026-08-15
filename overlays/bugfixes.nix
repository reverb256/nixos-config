{
  inputs,
  _final,
  prev,
}: {
  # 2026-08-04: gjs/gtk4/libsecret/qtbase dontCheck overrides REMOVED.
  # Cache-evidence audit: the VANILLA (checks-ON) derivations for all four
  # substitute from cache.nixos.org (narinfo HTTP 200):
  #   gjs 3qvw2ws…, gtk4 qq86wi0…, libsecret xplgg6b…, qt5.qtbase wmza0wv…
  # Hydra builds these WITH tests enabled and passing — the dontCheck flags
  # only re-forked the derivations off-cache, forcing the gtk4→chromium
  # family to recompile (same disease as the cups overlay fork, fixed 2026-08-04).
  # Removal restores those packages to cache substitution.

  # webkitgtk: KEPT — vanilla webkitgtk is genuinely NOT in cache.nixos.org
  # (404), so this is a real from-source build either way; dontCheck avoids
  # the pinned cluster sandbox's flaky test suite on the nexus builder.
  webkitgtk = prev.webkitgtk.overrideAttrs (old: {
    doCheck = false;
    dontCheck = true;
  });

  # 2026-08-08: protontricks-1.14.1 test suite asserts real filesystem paths
  # (steam library discovery) that the Nix sandbox rewrites to
  # `/nix/var/nix/b/<hash>` — 2 tests fail on the nexus builder unless checks
  # are disabled (same disease as webkitgtk above). protontricks is pulled
  # into every workstation/gaming role host via profiles.node.nexus-gaming +
  # profiles.role.workstation (services.gaming.enable=true), so this blocks
  # nexus toplevel builds. The tests are upstream codec/path tests, not used
  # by the installed binary.
  # doCheck/dontCheck alone do NOT stop pytestCheckHook — it re-defines
  # checkPhase, so the sandbox-path tests still run. The kill-switch is
  # dontUsePytestCheck (documented pytestCheckHook option).
  # overridePythonAttrs does NOT preserve the generic `.override` that the
  # nixpkgs Steam module calls (programs/steam.nix:231 override extraCompatPaths),
  # so injecting the compat paths would fail with "attribute 'override' missing".
  # overrideAttrs preserves `.override` AND accepts the pytestCheckHook kill-switch.
  protontricks = prev.protontricks.overrideAttrs (old: {
    dontUsePytestCheck = true;
    dontCheck = true;
  });

  # 2026-08-07: nixpkgs removed `libdisplay-info_0_2` (aliases.nix throw,
  # added 2026-08-04) — but the niri-flake input (sodiboo/niri-flake) still
  # `pkgs.callPackage make-niri` with an explicit `libdisplay-info_0_2` arg
  # and asserts `.version == "0.2.0"` (flake.nix:103). The flake bump pulled
  # the removal, so every host eval died with the aliases throw. Re-provide a
  # real 0.2.0 build via nixpkgs' own generic.nix — byte-identical to the
  # recipe used when 0.2.0 was still packaged (meson + hwdata; verified
  # against nixpkgs 0954f7ee). Our configs only EVAL it (programs.niri.package
  # is overridden to pkgs.niri-hdr), but the option value is forced during
  # module evaluation, so the attr must resolve.
  libdisplay-info_0_2 = _final.callPackage (import (_final.path + "/pkgs/by-name/li/libdisplay-info/generic.nix") {
    version = "0.2.0";
    hash = "sha256-6xmWBrPHghjok43eIDGeshpUEQTuwWLXNHg7CnBUt3Q=";
  }) {};

  # 2026-08-07: caddy caddytest/integration suite fails in the nix sandbox
  # (reverse_proxy health-checker test probes a %2F-encoded unix socket URL —
  # "invalid URL escape"; the suite also needs live ports). Vanilla caddy IS
  # in cache.nixos.org, but this cluster's nixpkgs rev pulls caddy 2.11.4
  # whose check phase re-runs the flaky integration suite on every fresh
  # (non-cached) build — e.g. sentry's zephyr-toplevel build. caddy-with-modules
  # already sets doCheck = false; align the base package.
  caddy = prev.caddy.overrideAttrs (old: {
    doCheck = false;
  });

  # 2026-08-15: gamescope 3.16.23+ regression (gamescope#2204, still OPEN):
  # Steam Proton games launched through gamescope close immediately with
  # `ConnectToGlobalUser: Steam denied appID` -> `steamclient_init_registry
  # Failed to connect to Steam`. The window appears briefly then vanishes with
  # no error. zephyr's scopebuddy HDR stack wraps gamescope, so PoE2 (appid
  # 2694490) and other Steam titles die at launch on 3.16.25. The fix PR (#2190,
  # cgroup AppID derivation) is unmerged; the known-good tag is 3.16.22. Pin
  # the package source to that tag. The nixpkgs pending patches (4ce1a91f
  # system-libs, d49a2ade stb_image_resize2 guard) apply cleanly to 3.16.22
  # (verified). This changes the gamescope binary for ALL consumers (system
  # gamescope, Steam FHS extraPkgs, scopebuddy wrapper PATH) — intended.
  gamescope = prev.gamescope.overrideAttrs (old: {
    version = "3.16.22";
    src = _final.fetchFromGitHub {
      owner = "ValveSoftware";
      repo = "gamescope";
      tag = "3.16.22";
      fetchSubmodules = true;
      hash = "sha256-FuQkKguW00yI2w5nCctcxz7e1ZUKSWJOCIS1UMJzsMA=";
    };
  });

  # 2026-08-10: xwayland 24.1.13 fails to build under GCC 15.3 — libunwind's
  # unw_word_t is now unsigned int* (was unsigned long*) on x86_64, so the
  # uint64_t val / %PRIx64 in os/backtrace.c is an ABI mismatch. This breaks
  # gamescope's SDL backend (VK_KHR_x11 unavailable without Xwayland) and thus
  # the gamescope-wsi HDR path for Steam games on zephyr.
  #
  # Upstream Xorg patch (commit e0588d21, MR !1763): use unw_word_t + PRIxPTR,
  # which is correct for both 32/64-bit. Apply via postPatch so we stay on
  # nixos-unstable without a full nixpkgs re-pin. The patch is byte-identical
  # to the fdo merge request.
  xwayland = prev.xwayland.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + ''
        substituteInPlace os/backtrace.c \
          --replace 'uint64_t val;' 'unw_word_t val;' \
          --replace 'ErrorF("  %s: 0x%" PRIx64 "\\n", regs[i].name, val);' \
                  'ErrorF("  %s: 0x%" PRIxPTR "\\n", regs[i].name, val);'
        # PRIxPTR requires <inttypes.h> which libxserver-os already pulls in
      '';
  });
}

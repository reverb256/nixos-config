{ inputs, _final, prev }:
{
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
  protontricks = prev.protontricks.overridePythonAttrs (old: {
    dontUsePytestCheck = true;
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
  }) { };

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
}

{ inputs, _final, prev }:

{
  # CRITICAL: Do NOT use `pkgs.X = ...` pattern in this overlay!
  # Using `pkgs.` as a prefix creates _final.pkgs = { X = ...; },
  # which SHADOWS the full package set in callPackage contexts.
  # When perl-packages.nix does `buildInputs = [ pkgs.gettext ]`,
  # it resolves pkgs to _final.pkgs (a tiny attrset) instead of _final.
  # This causes "attribute 'gettext' missing" errors.
  #
  # Use top-level attribute names instead: `gjs = ...` not `pkgs.gjs = ...`.

  gjs = prev.gjs.overrideAttrs (old: {
    doCheck = false;
    dontCheck = true;
  });

  gtk4 = prev.gtk4.overrideAttrs (old: {
    doCheck = false;
    dontCheck = true;
  });

  webkitgtk = prev.webkitgtk.overrideAttrs (old: {
    doCheck = false;
    dontCheck = true;
  });

  # Preserve all other qt5 packages — qt5.qtbase replaces only qtbase
  qt5 = prev.qt5 // {
    qtbase = prev.qt5.qtbase.overrideAttrs (old: {
      doCheck = false;
      dontCheck = true;
    });
  };

  # 2026-07-30: nixpkgs-unstable: tcl-8_6 alias regression in python-packages.nix.
  # Override the tkinter build to use prev.tcl (which is 8.6) instead.
  "python3.14-tkinter" = prev.python3Packages.tkinter.override {
    tcl = _final.tcl;
    tk = _final.tk;
  };

  # 2026-07-30: nixpkgs-unstable: gettext missing from perl package buildInputs
  # in the perl-packages.nix evaluation context. Ensure gettext is re-exported
  # from prev so `pkgs.gettext` resolves correctly for build inputs.
  inherit (prev) gettext;
}

{ inputs, _final, prev }:

{
  pkgs.gjs = prev.gjs.overrideAttrs (old: {
    doCheck = false;
    dontCheck = true;
  });

  pkgs.gtk4 = prev.gtk4.overrideAttrs (old: {
    doCheck = false;
    dontCheck = true;
  });

  pkgs.webkitgtk = prev.webkitgtk.overrideAttrs (old: {
    doCheck = false;
    dontCheck = true;
  });

  pkgs.qt5.qtbase = prev.qt5.qtbase.overrideAttrs (old: {
    doCheck = false;
    dontCheck = true;
  });

  # 2026-07-30: nixpkgs-unstable: tcl-8_6 alias regression in python-packages.nix.
  # Override the tkinter build to use prev.tcl (which is 8.6) instead.
  "python3.14-tkinter" = prev.python3Packages.tkinter.override {
    tcl = _final.tcl;
    tk = _final.tk;
  };
}

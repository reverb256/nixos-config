{ config, lib, pkgs, ... }:
{
  nixpkgs.overlays = [
    (final: prev: {
      noctalia-shell = prev.noctalia-shell.overrideAttrs (old: {
        preFixup = (old.preFixup or "") + ''
          ${prev.python3}/bin/python3 ${./patch-noctalia-brightness.py} \
            $out/share/noctalia-shell/Services/Hardware/BrightnessService.qml
        '';
      });
    })
  ];
}

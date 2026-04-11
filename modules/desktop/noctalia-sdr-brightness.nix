# Patch noctalia-shell BrightnessService.qml to support niri SDR brightness
# for monitors without DDC/CI or backlight (e.g. Samsung HDMI TV)
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

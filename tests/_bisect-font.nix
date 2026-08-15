{ pkgs ? import <nixpkgs> { } }:
let
  inherit (pkgs) lib;
  stylixNix = /etc/nixos/modules/desktop/stylix.nix;
  stylixContent = builtins.readFile stylixNix;
  expectedFonts = {
    sansSerif = "Inter";
    serif = "DejaVu Serif";
    monospace = "JetBrainsMono Nerd Font";
    emoji = "Noto Color Emoji";
  };
  declaresFamily = family: name:
    (lib.strings.hasInfix "fonts.${family} = {" stylixContent
      || lib.strings.hasInfix "${family} = {" stylixContent)
    && lib.strings.hasInfix "\"${name}\"" stylixContent;
  fontChecks = lib.mapAttrs'
    (family: name: lib.nameValuePair "stylix-declares-${family}" (declaresFamily family name))
    expectedFonts;
in
{
  justFontChecks = fontChecks;
}

{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs) lib;
  source = builtins.readFile ../modules/profiles/portable-usb.nix;
  has = needle: lib.strings.hasInfix needle source;

  checks = {
    disablesHostModelPayload = has "modelAvailable = false;";
    removesHostOnlyRunCommand = !(has "pkgs.runCommand \\\"bonsai-1bit-model\\\"");
    guardsTmpfiles = has "systemd.tmpfiles.rules = lib.mkIf modelAvailable";
    guardsService = has "systemd.services.bonsai-local = lib.mkIf modelAvailable";
    guardsHermes = has "environment.etc.\"hermes/config.toml\" = lib.mkIf modelAvailable";
  };

  failures = lib.filterAttrs (_: passed: !passed) checks;
in {
  inherit checks failures;
  passed = failures == {};
}

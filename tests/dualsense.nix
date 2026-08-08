{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs) lib;
  moduleSource = builtins.readFile ../modules/gaming/dualsense.nix;
  defaultSource = builtins.readFile ../modules/default.nix;
  commonSource = builtins.readFile ../common-modules-list.nix;
  hosts = ["zephyr" "nexus" "forge" "sentry"];
  hostSource = host: builtins.readFile ../hosts/${host}/configuration.nix;
  checks = {
    moduleImportedByDefault = lib.strings.hasInfix "./gaming/dualsense.nix" defaultSource;
    defaultImportedByCommon = lib.strings.hasInfix "./modules/default.nix" commonSource;
    hidPlaystation = lib.strings.hasInfix "hid_playstation" moduleSource;
    usbAndBluetoothUaccess =
      lib.strings.hasInfix "0ce6" moduleSource
      && lib.strings.hasInfix "0df2" moduleSource
      && lib.strings.hasInfix "uaccess" moduleSource;
    sdlDatabase =
      lib.strings.hasInfix "sdl2-dualsense-db" moduleSource
      && lib.strings.hasInfix "SDL_GAMECONTROLLERCONFIG_FILE" moduleSource;
    bluetooth =
      lib.strings.hasInfix "hardware.bluetooth" moduleSource
      && lib.strings.hasInfix "powerOnBoot" moduleSource;
    diagnostic =
      lib.strings.hasInfix "dualsense-diagnose" moduleSource
      && lib.strings.hasInfix "/dev/input/" moduleSource;
    noKernelDeadzoneMutation =
      !(lib.strings.hasInfix "set-evdev-deadzone" moduleSource)
      && !(lib.strings.hasInfix "EVIOCSABS" moduleSource);
    noGamingStackExpansion =
      !(lib.strings.hasInfix "programs.steam" moduleSource)
      && !(lib.strings.hasInfix "programs.gamescope" moduleSource);
    allHostsImportCommon = builtins.all (
      host: lib.strings.hasInfix "../../modules/default.nix" (hostSource host)
    ) hosts;
  };
  failures = builtins.attrNames (lib.filterAttrs (_: passed: !passed) checks);
in {
  inherit checks failures;
  passed = failures == [];
}

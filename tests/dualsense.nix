{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs) lib;
  moduleSource = builtins.readFile ../modules/gaming/dualsense.nix;
  gamingModulesSource = builtins.readFile ../modules/gaming-modules.nix;
  inventorySource = builtins.readFile ../contracts/host-inventory.nix;
  commonSource = builtins.readFile ../common-modules-list.nix;
  hosts = ["zephyr" "nexus" "forge" "sentry"];
  hostSource = host: builtins.readFile ../hosts/${host}/configuration.nix;

  checks = {
    # dualsense is bundled in gaming-modules.nix (desktop-hosts-only bundle),
    # no longer imported from modules/default.nix (which is commonModules for
    # every host). The 2026-08-20 refactor moved the whole gaming/VR/Steam
    # closure off headless sentry/forge.
    moduleImportedByDefault = lib.strings.hasInfix "./gaming/dualsense.nix" gamingModulesSource;
    notImportedFromDefault = !(lib.strings.hasInfix "./gaming/dualsense.nix" (builtins.readFile ../modules/default.nix));
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
    # Desktop hosts (zephyr, nexus) pull gaming-modules via extraModules
    # in contracts/host-inventory.nix (the single wiring point). The test
    # checks the inventory declares it — host configs don't reference it
    # directly (they inherit via flake.nix consuming the inventory).
    gamingOnZephyrAndNexus =
      lib.strings.hasInfix "gaming-modules.nix" inventorySource;
    gamingOffForgeAndSentry = builtins.all (
      host: !(lib.strings.hasInfix "gaming-modules.nix" (hostSource host))
    ) ["forge" "sentry"];
    allHostsImportCommon = builtins.all (
      host: lib.strings.hasInfix "../../modules/default.nix" (hostSource host)
    ) hosts;
  };
  failures = builtins.attrNames (lib.filterAttrs (_: passed: !passed) checks);
in {
  inherit checks failures;
  passed = failures == [];
}

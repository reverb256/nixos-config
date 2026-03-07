# Hlissner-Style NixOS Configuration Refactor

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor the NixOS configuration to follow hlissner/dotfiles patterns: better separation of concerns, modular home-manager, profile system, auto-import helpers, and extracted shell scripts.

**Architecture:**
1. **lib/**: Custom library with mapModules, mapHosts, and helper functions
2. **modules/home-manager/**: Extracted user-space configs (browser, discord, services)
3. **modules/profiles/**: Hardware, role, and network profiles for host composition
4. **scripts/**: Extract embedded shell scripts from Nix expressions
5. **flake.nix**: Refactored to use mkFlake pattern with cleaner host definitions

**Tech Stack:** Nix flakes, NixOS modules, Home Manager, systemd, Bash scripts

**Reference:** https://github.com/hlissner/dotfiles

---

## Pre-Implementation Steps

### Task 0: Prepare Repository

**Files:**
- Modify: working tree

**Step 0.1: Commit current changes**

```bash
git add modules/desktop/spotify-spotx.nix
git commit -m "chore(spotify): Commit pending changes before refactor"
```

**Step 0.2: Create refactor branch**

```bash
git checkout -b refactor/hlissner-style
git branch --show-current
```
Expected: `refactor/hlissner-style`

**Step 0.3: Verify starting state**

```bash
nix flake check
```
Expected: Success (no errors)

---

## Phase 1: Create lib/ Infrastructure

### Task 1: Create lib/ Directory Structure

**Files:**
- Create: `lib/default.nix`
- Create: `lib/attrs.nix`
- Create: `lib/modules.nix`

**Step 1.1: Create lib/attrs.nix**

```nix
# lib/attrs.nix --- Attribute set utilities
#
# Heavily inspired by hlissner/dotfiles
# Provides helpers for working with nested attribute sets

{ lib }:

with builtins; with lib;
let
  # Flatten an attrset, concatenating names with '.'
  # flattenAttrs { a.b = 1; c = 2; } => { "a.b" = 1; c = 2; }
  flattenAttrs = prefix: attrs:
    foldl' (acc: name:
      let
        v = getAttr name attrs;
        newName = if prefix == "" then name else "${prefix}.${name}";
      in
        if isAttrs v && !isDerivation v
        then acc // flattenAttrs newName v
        else acc // {${newName} = v}
    ) {} (attrNames attrs);
in
{
  inherit
    flattenAttrs
    ;
}
```

**Step 1.2: Create lib/modules.nix**

```nix
# lib/modules.nix --- Module discovery and loading utilities
#
# Heavily inspired by hlissner/dotfiles
# Provides mapModules, mapModulesRec, mapHosts for auto-discovery

{ lib, attrs }:

let
  inherit (builtins)
    attrValues
    readDir
    pathExists
    concatLists
    attrNames
    isAttrs
    mapAttrs;

  inherit (lib)
    id
    mapAttrs'
    filterAttrs
    hasPrefix
    hasSuffix
    nameValuePair
    removeSuffix
   ;

  # Helper to check if path is a directory with default.nix
  hasDefaultNix = path:
    pathExists "${path}/default.nix";

  # Helper to check if file is a Nix file (but not flake.nix or default.nix)
  isNixFile = name: v:
    v == "regular" &&
    name != "default.nix" &&
    name != "flake.nix" &&
    hasSuffix ".nix" name;
in
rec {
  # Map modules in a directory to attrset
  # Directories become named after their dirname, files lose .nix suffix
  # Skips hidden (starts with _) entries
  #
  # mapModules ./modules → { desktop = import ./modules/desktop; ... }
  mapModules = dir: fn:
    mapAttrs'
      (n: v:
        let path = "${toString dir}/${n}"; in
        if v == "directory" && hasDefaultNix path
        then nameValuePair n (fn path)
        else if isNixFile n v
        then nameValuePair (removeSuffix ".nix" n) (fn path)
        else nameValuePair "" null)
      (n: v: v != null && !(hasPrefix "_" n))
      (readDir dir);

  # Map modules to a list of values
  mapModules' = dir: fn:
    attrValues (mapModules dir fn);

  # Recursively map modules, preserving directory structure
  # mapModulesRec ./modules → { desktop = { apps = { ... }; }; ... }
  mapModulesRec = dir: fn:
    mapAttrs'
      (n: v:
        let path = "${toString dir}/${n}"; in
        if v == "directory"
        then nameValuePair n (mapModulesRec path fn)
        else if isNixFile n v
        then nameValuePair (removeSuffix ".nix" n) (fn path)
        else nameValuePair "" null)
      (n: v: v != null && !(hasPrefix "_" n))
      (readDir dir);

  # Recursively map modules to flat list
  mapModulesRec' = dir: fn:
    let
      dirs =
        mapAttrsToList
          (k: _: "${dir}/${k}")
          (filterAttrs
            (n: v: v == "directory"
                   && !(hasPrefix "_" n)
                   && !(pathExists "${dir}/${n}/.noload"))
            (readDir dir));
      files = attrValues (mapModules dir id);
      paths = files ++ concatLists (map (d: mapModulesRec' d id) dirs);
    in map fn paths;

  # Map host configurations from a directory
  # Each host directory should contain a configuration.nix
  mapHosts = dir:
    mapModules dir (path: {
      inherit path;
      config = import path;
    });
}
```

**Step 1.3: Create lib/default.nix**

```nix
# lib/default.nix --- Custom library entry point
#
# Combines attrs and modules libraries, extends nixpkgs lib

{ self, lib, pkgs, ... }:

let
  inherit (builtins)
    mapAttrs
    intersectAttrs
    functionArgs
    attrValues;

  inherit (lib)
    foldl
    mapAttrs'
    nameValuePair;

  # Import sub-libraries
  attrs   = import ./attrs.nix   { inherit lib; };
  modules = import ./modules.nix { inherit lib attrs; };
in
{
  inherit attrs modules;

  # Re-export nixpkgs lib for convenience
  inherit (lib)
    attrNames
    attrValues
    mapAttrs
    mapAttrs'
    filterAttrs
    hasPrefix
    hasSuffix
    removeSuffix
    nameValuePair
    optional
    optionalString
    mkIf
    mkEnableOption
    mkOption
    mkDefault
    mkForce
    mkOrder
    types
    literalExpression
    genAttrs
    listToAttrs
    foldl'
    concatMap
    concatLists
    imap
    imap0
    zipAttrsWith
    zipAttrsWithNames
    ;
}
```

**Step 1.4: Verify lib structure**

```bash
tree lib/
```
Expected:
```
lib/
├── attrs.nix
├── default.nix
└── modules.nix
```

**Step 1.5: Test lib can be imported**

```bash
nix repl --expr 'import ./lib { self = ./.; lib = import <nixpkgs/lib>; pkgs = import <nixpkgs> {}; }'
```
Expected: No errors, can access `lib.modules.mapModules`

**Step 1.6: Commit**

```bash
git add lib/
git commit -m "refactor(lib): Add custom library infrastructure (attrs, modules)"
```

---

## Phase 2: Create modules/home-manager/ System

### Task 2: Create Home Manager Module Structure

**Files:**
- Create: `modules/home-manager/default.nix`
- Create: `modules/home-manager/browser.nix`
- Create: `modules/home-manager/discord.nix`
- Create: `modules/home-manager/services.nix`
- Create: `modules/home-manager/xdg.nix`

**Step 2.1: Create modules/home-manager/xdg.nix**

```nix
# modules/home-manager/xdg.nix --- XDG Base Directory compliance
#
# Enforces XDG standards and sets environment variables early
# Programs read XDG vars before Home Manager runs, so we set at session level

{ config, lib, pkgs, ... }:

let
  cfg = config.hm-xdg;
in
{
  options.hm-xdg = with lib.types; {
    enable = lib.mkEnableOption "XDG compliance enforcement";

    cacheDir = lib.mkOption {
      type = str;
      default = "${config.home.homeDirectory}/.cache";
      description = "XDG cache directory";
    };

    configDir = lib.mkOption {
      type = str;
      default = "${config.home.homeDirectory}/.config";
      description = "XDG config directory";
    };

    dataDir = lib.mkOption {
      type = str;
      default = "${config.home.homeDirectory}/.local/share";
      description = "XDG data directory";
    };

    stateDir = lib.mkOption {
      type = str;
      default = "${config.home.homeDirectory}/.local/state";
      description = "XDG state directory";
    };

    binDir = lib.mkOption {
      type = str;
      default = "${config.home.homeDirectory}/.local/bin";
      description = "XDG bin directory";
    };

    # Non-standard: Jail for stubborn programs
    fakeDir = lib.mkOption {
      type = str;
      default = "${config.home.homeDirectory}/.local/user";
      description = "Directory for programs that don't respect XDG";
    };
  };

  config = lib.mkIf cfg.enable {
    # Set XDG variables early (order 10 = before most things)
    environment.sessionVariables = lib.mkOrder 10 {
      XDG_BIN_HOME    = cfg.binDir;
      XDG_CACHE_HOME  = cfg.cacheDir;
      XDG_CONFIG_HOME = cfg.configDir;
      XDG_DATA_HOME   = cfg.dataDir;
      XDG_STATE_HOME  = cfg.stateDir;
      XDG_FAKE_HOME   = cfg.fakeDir;
      XDG_DESKTOP_DIR = cfg.fakeDir;
    };

    # Ensure bin directory is in PATH
    environment.localBinInPath = true;

    # Home Manager configuration
    home-manager.users.j_kro.xdg = {
      enable = true;
      cacheHome  = lib.mkForce cfg.cacheDir;
      configHome = lib.mkForce cfg.configDir;
      dataHome   = lib.mkForce cfg.dataDir;
      stateHome  = lib.mkForce cfg.stateDir;
    };
  };
}
```

**Step 2.2: Create modules/home-manager/default.nix**

```nix
# modules/home-manager/default.nix --- Home Manager integration module
#
# Wraps Home Manager as a NixOS module with clean API
# Inspired by hlissner/dotfiles modules/home.nix

{ config, lib, pkgs, ... }:

let
  cfg = config.home-manager-wrapper;
in
{
  imports = [
    ./xdg.nix
  ];

  options.home-manager-wrapper = with lib.types; {
    enable = lib.mkEnableOption "Home Manager wrapper";

    user = lib.mkOption {
      type = str;
      default = "j_kro";
      description = "Username to manage";
    };

    # Convenience shortcuts
    file = lib.mkOption {
      type = attrs;
      default = {};
      description = "Files to place in $HOME";
    };

    configFile = lib.mkOption {
      type = attrs;
      default = {};
      description = "Files to place in $XDG_CONFIG_HOME";
    };

    dataFile = lib.mkOption {
      type = attrs;
      default = {};
      description = "Files to place in $XDG_DATA_HOME";
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable Home Manager as NixOS module
    home-manager = {
      useUserPackages = true;
      users.${cfg.user} = {
        home.username = cfg.user;
        home.homeDirectory = "/home/${cfg.user}";
        home.stateVersion = config.system.stateVersion;

        # Map convenience shortcuts to actual Home Manager options
        home.file = lib.mkAliasDefinitions config.home-manager-wrapper.options.file;
        xdg.configFile = lib.mkAliasDefinitions config.home-manager-wrapper.options.configFile;
        xdg.dataFile = lib.mkAliasDefinitions config.home-manager-wrapper.options.dataFile;
      };
    };
  };
}
```

**Step 2.3: Create modules/home-manager/browser.nix**

Extracted from `hosts/zephyr/configuration.nix` lines ~300-500 (Zen browser config):

```nix
# modules/home-manager/browser.nix --- Zen Browser configuration

{ config, lib, pkgs, ... }:

let
  cfg = config.home-manager-browser;
in
{
  options.home-manager-browser = with lib.types; {
    enable = lib.mkEnableOption "Zen Browser configuration";
  };

  config = lib.mkIf cfg.enable {
    home-manager.users.j_kro = {
      imports = [
        inputs.zen-browser.homeModules.twilight
      ];

      programs.zen-browser = {
        enable = true;
        suppressXdgMigrationWarning = true;

        # PWA Support
        nativeMessagingHosts = [pkgs.firefoxpwa];

        policies = {
          DisableAppUpdate = true;
          DisableTelemetry = true;
          DisableFirefoxStudies = true;
          DisableFeedbackCommands = true;
          DisablePocket = true;
          NoDefaultBookmarks = true;
          OfferToSaveLogins = false;
          EnableTrackingProtection = {
            Value = true;
            Locked = true;
            Cryptomining = true;
            Fingerprinting = true;
          };

          ExtensionSettings = {
            # Essential Security (force-installed)
            "uBlock0@raymondhill.net" = {
              installation_mode = "force_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
            };
            "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
              installation_mode = "force_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
            };
            "jid1-BoFifL9Vbdl2zQ@jetpack" = {
              installation_mode = "force_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/decentraleyes/latest.xpi";
            };
            "addon@darkreader.org" = {
              installation_mode = "force_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi";
            };

            # User-Configurable (allows per-site exceptions)
            "jid1-MnnxcxisBPnSXQ@jetpack" = {
              installation_mode = "normal_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/privacy-badger17/latest.xpi";
            };
            "{73a6fe31-595d-460b-a920-fcc0f8843232}" = {
              installation_mode = "normal_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/noscript/latest.xpi";
            };
            "{74145f27-f039-47ce-a470-a662b129930a}" = {
              installation_mode = "normal_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/clearurls/latest.xpi";
            };
            "CookieAutoDelete@kennydo.com" = {
              installation_mode = "normal_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/cookie-autodelete/latest.xpi";
            };
            "{48748554-4c01-49e8-94af-79662bf34d50}" = {
              installation_mode = "normal_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/privacy-pass/latest.xpi";
            };
          };
        };

        profiles.default = {
          id = 0;
          name = "default";
          isDefault = true;

          containersForce = true;
          pinsForce = true;
          spacesForce = true;

          extraConfig = ''
            // Zen-specific preferences
            user_pref("zen.theme.sidebar", "auto");
            user_pref("zen.view.compact", true);
            user_pref("zen.workspaces.vertical", true);

            // Performance optimizations
            user_pref("gfx.webrender.all", true);
            user_pref("media.ffmpeg.vaapi.enabled", true);
            user_pref("widget.dmabuf.force-enabled", true);

            // Privacy enhancements
            user_pref("privacy.resistFingerprinting", true);
            user_pref("network.http.referer.spoofSource", true);
            user_pref("privacy.trackingprotection.enabled", true);
          '';

          containers = {
            "Dev" = { color = "blue"; icon = "fingerprint"; id = 1; };
            "Personal" = { color = "green"; icon = "briefcase"; id = 2; };
            "Finance" = { color = "orange"; icon = "dollar"; id = 3; };
            "Gaming" = { color = "purple"; icon = "circle"; id = 4; };
            "AI" = { color = "turquoise"; icon = "pet"; id = 5; };
          };

          spaces = {
            "Dev" = {
              id = "dev-1f8a6f7c-3b59-4d65-9c1f-0a3e9a6f1b01";
              icon = "";
              position = 1000;
              container = 1;
            };
            "AI" = {
              id = "ai-2b9d4c41-6a8e-4c9b-9a44-6d1c7f2e8b02";
              icon = "";
              position = 2000;
              container = 5;
            };
            "Gaming" = {
              id = "game-3c7e2b6d-9f5a-4b41-8f77-1e9c5a4d2c03";
              icon = "";
              position = 3000;
              container = 4;
            };
            "Personal" = {
              id = "personal-4d8f3c7e-0a6b-5d52-9f88-2f0d6b5e3d14";
              icon = "";
              position = 4000;
              container = 2;
            };
            "Mining" = {
              id = "mining-5e9g4d8f-1b7c-6e63-0a99-3g1e7c6f4e25";
              icon = "";
              position = 5000;
              container = 3;
            };
            "System" = {
              id = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
              icon = "";
              position = 6000;
              container = 2;
            };
          };

          pins = {
            "GitHub" = {
              id = "pin-gh-001";
              url = "https://github.com";
              workspace = "dev-1f8a6f7c-3b59-4d65-9c1f-0a3e9a6f1b01";
              container = 1;
              position = 100;
              isEssential = true;
            };
            "NixOS Wiki" = {
              id = "pin-nw-002";
              url = "https://nixos.wiki";
              workspace = "dev-1f8a6f7c-3b59-4d65-9c1f-0a3e9a6f1b01";
              container = 1;
              position = 110;
            };
            "Claude" = {
              id = "pin-ai-001";
              url = "https://claude.ai";
              workspace = "ai-2b9d4c41-6a8e-4c9b-9a44-6d1c7f2e8b02";
              container = 5;
              position = 200;
              isEssential = true;
            };
            "LM Studio" = {
              id = "pin-ai-002";
              url = "https://lmstudio.ai";
              workspace = "ai-2b9d4c41-6a8e-4c9b-9a44-6d1c7f2e8b02";
              container = 5;
              position = 210;
            };
            "Discord" = {
              id = "pin-game-001";
              url = "https://discord.com";
              workspace = "game-3c7e2b6d-9f5a-4b41-8f77-1e9c5a4d2c03";
              container = 4;
              position = 300;
              isEssential = true;
            };
            "Steam" = {
              id = "pin-game-002";
              url = "https://store.steampowered.com";
              workspace = "game-3c7e2b6d-9f5a-4b41-8f77-1e9c5a4d2c03";
              container = 4;
              position = 310;
            };
            "Gmail" = {
              id = "pin-per-001";
              url = "https://mail.google.com";
              workspace = "personal-4d8f3c7e-0a6b-5d52-9f88-2f0d6b5e3d14";
              container = 2;
              position = 400;
            };
            "Outlook" = {
              id = "pin-per-003";
              url = "https://outlook.live.com/mail";
              workspace = "personal-4d8f3c7e-0a6b-5d52-9f88-2f0d6b5e3d14";
              container = 2;
              position = 405;
            };
            "Reddit" = {
              id = "pin-per-002";
              url = "https://reddit.com";
              workspace = "personal-4d8f3c7e-0a6b-5d52-9f88-2f0d6b5e3d14";
              container = 2;
              position = 410;
            };
            "NiceHash" = {
              id = "pin-min-001";
              url = "https://www.nicehash.com";
              workspace = "mining-5e9g4d8f-1b7c-6e63-0a99-3g1e7c6f4e25";
              container = 3;
              position = 500;
            };
            "MiningPoolStats" = {
              id = "pin-min-002";
              url = "https://miningpoolstats.stream";
              workspace = "mining-5e9g4d8f-1b7c-6e63-0a99-3g1e7c6f4e25";
              container = 3;
              position = 510;
            };
            "Tailscale" = {
              id = "pin-sys-001";
              url = "https://login.tailscale.com";
              workspace = "system-6f0a5e9g-2c8d-7f74-1b00-4h2f8d7g5f36";
              container = 2;
              position = 600;
              isEssential = true;
            };
          };

          search = {
            force = true;
            default = "google";
            privateDefault = "ddg";
            order = [
              "google" "ddg" "github" "nixos-packages" "nixos-options"
              "nixos-wiki" "home-manager" "mynixos" "noogle" "huggingface"
              "pypi" "stackoverflow" "mdn"
            ];
            engines = {
              google = {
                urls = [{template = "https://www.google.com/search?q={searchTerms}";}];
                icon = "https://www.google.com/favicon.ico";
                definedAliases = ["@g" "@google"];
              };
              ddg = {
                urls = [{template = "https://duckduckgo.com/?q={searchTerms}";}];
                icon = "https://duckduckgo.com/favicon.ico";
                definedAliases = ["@d" "@ddg"];
              };
              github = {
                urls = [{template = "https://github.com/search?q={searchTerms}&type=repositories";}];
                icon = "https://github.com/favicon.ico";
                definedAliases = ["@gh" "@github"];
              };
              nixos-packages = {
                urls = [{
                  template = "https://search.nixos.org/packages";
                  params = [{name = "type"; value = "packages";} {name = "query"; value = "{searchTerms}";}];
                }];
                icon = "https://nixos.org/favicon.ico";
                definedAliases = ["@np" "@nixpkgs"];
              };
              nixos-options = {
                urls = [{
                  template = "https://search.nixos.org/options";
                  params = [{name = "type"; value = "packages";} {name = "query"; value = "{searchTerms}";}];
                }];
                icon = "https://nixos.org/favicon.ico";
                definedAliases = ["@no" "@nixopts"];
              };
              nixos-wiki = {
                urls = [{template = "https://nixos.wiki/index.php?search={searchTerms}";}];
                icon = "https://nixos.wiki/favicon.ico";
                definedAliases = ["@nw"];
              };
              home-manager = {
                urls = [{template = "https://home-manager-options.extranix.com/?query={searchTerms}";}];
                icon = "https://nixos.org/favicon.ico";
                definedAliases = ["@hm"];
              };
              mynixos = {
                urls = [{template = "https://mynixos.com/search?q={searchTerms}";}];
                icon = "https://mynixos.com/favicon.ico";
                definedAliases = ["@mn" "@mynixos"];
              };
              noogle = {
                urls = [{template = "https://noogle.dev/q?term={searchTerms}";}];
                icon = "https://nixos.org/favicon.ico";
                definedAliases = ["@ng" "@noogle"];
              };
              huggingface = {
                urls = [{template = "https://huggingface.co/search?q={searchTerms}";}];
                icon = "https://huggingface.co/favicon.ico";
                definedAliases = ["@hf" "@huggingface"];
              };
              pypi = {
                urls = [{template = "https://pypi.org/search/?q={searchTerms}";}];
                icon = "https://pypi.org/favicon.ico";
                definedAliases = ["@pypi"];
              };
              stackoverflow = {
                urls = [{template = "https://stackoverflow.com/search?q={searchTerms}";}];
                icon = "https://stackoverflow.com/favicon.ico";
                definedAliases = ["@so" "@stack"];
              };
              mdn = {
                urls = [{template = "https://developer.mozilla.org/en-US/search?q={searchTerms}";}];
                icon = "https://developer.mozilla.org/favicon.ico";
                definedAliases = ["@mdn"];
              };
            };
          };
        };
      };
    };
  };
}
```

**Step 2.4: Create modules/home-manager/discord.nix**

Extracted from `hosts/zephyr/configuration.nix` lines ~500-600 (Vesktop/Nixcord config):

```nix
# modules/home-manager/discord.nix --- Discord/Vesktop configuration

{ config, lib, pkgs, ... }:

let
  cfg = config.home-manager-discord;
in
{
  options.home-manager-discord = with lib.types; {
    enable = lib.mkEnableOption "Discord/Vesktop configuration";
  };

  config = lib.mkIf cfg.enable {
    home-manager.users.j_kro = {
      imports = [
        inputs.nixcord.homeModules.nixcord
      ];

      # Mask Vesktop XDG autostart file
      xdg.configFile."autostart/vesktop.desktop".text = ''
        [Desktop Entry]
        Hidden=true
        X-GNOME-Autostart-enabled=false
        X-KDE-autostart-after-panel=false
      '';

      programs.nixcord = {
        enable = true;
        discord.enable = false;
        vesktop.enable = true;

        vesktopConfig = {
          tray = false;
          trayIcon = false;
          openHidden = false;

          plugins = {
            XSOverlay = {
              enable = true;
              dmNotifications = true;
              groupDmNotifications = true;
              serverNotifications = true;
              callNotifications = true;
              channelPingColor = "#8a2be2";
              pingColor = "#7289da";
              timeout = 3;
              volume = 0.2;
              opacity = 1.0;
            };
            fakeNitro = {
              enable = true;
              enableEmojiBypass = true;
              enableStickerBypass = true;
              enableStreamBypass = true;
              emojiSize = 48.0;
            };
            USRBG = {
              enable = true;
              nitroFirst = true;
              voiceBackground = true;
            };
            ReviewDB = {
              enable = true;
            };
          };
        };
      };

      # Autostart Vesktop
      systemd.user.services.vesktop-autostart = {
        Unit = {
          Description = "Vesktop autostart";
          After = ["graphical-session-pre.target" "plasma-plasmashell.service"];
          PartOf = ["graphical-session.target"];
          Wants = ["plasma-plasmashell.service"];
        };
        Service = {
          Type = "simple";
          Environment = [
            "XDG_CURRENT_DESKTOP=KDE"
            "ELECTRON_OZONE_PLATFORM_HINT=x11"
          ];
          ExecStart = "${pkgs.vesktop}/bin/vesktop --enable-speech-dispatcher --enable-features=UseOzonePlatform --ozone-platform-hint=x11 --start-minimized";
          Restart = "on-failure";
          RestartSec = 5;
        };
        Install = {
          WantedBy = ["graphical-session.target"];
        };
      };
    };
  };
}
```

**Step 2.5: Create modules/home-manager/services.nix**

For user systemd services and environment variables:

```nix
# modules/home-manager/services.nix --- User services and environment

{ config, lib, pkgs, ... }:

let
  cfg = config.home-manager-services;
in
{
  options.home-manager-services = with lib.types; {
    enable = lib.mkEnableOption "Home Manager services configuration";

    hfToken = lib.mkOption {
      type = nullOr str;
      default = null;
      description = "HuggingFace token for systemd environment";
    };
  };

  config = lib.mkIf cfg.enable {
    home-manager.users.j_kro = {
      # systemd user environment for secrets
      systemd.user.sessionVariables = lib.mkIf (cfg.hfToken != null) {
        HF_TOKEN = cfg.hfToken;
      };
    };
  };
}
```

**Step 2.6: Update modules/default.nix to import home-manager**

Modify `modules/default.nix` - add to imports list:

```nix
imports = [
  # ... existing imports ...

  # Home Manager integration
  ./home-manager/default.nix
];
```

**Step 2.7: Commit**

```bash
git add modules/home-manager/
git commit -m "refactor(home-manager): Add home-manager module structure with browser, discord, xdg, services"
```

---

## Phase 3: Create modules/profiles/ System

### Task 3: Create Profile Module Structure

**Files:**
- Create: `modules/profiles/default.nix`
- Create: `modules/profiles/hardware/default.nix`
- Create: `modules/profiles/hardware/cpu.nix`
- Create: `modules/profiles/hardware/gpu.nix`
- Create: `modules/profiles/role/default.nix`
- Create: `modules/profiles/network/default.nix`

**Step 3.1: Create modules/profiles/default.nix**

```nix
# modules/profiles/default.nix --- Profile system entry point
#
# Provides hardware, role, and network profiles for host composition
# Inspired by hlissner/dotfiles modules/profiles/default.nix

{ config, lib, ... }:

{
  imports = [
    ./hardware
    ./role
    ./network
  ];

  options.profiles = with lib.types; {
    hardware = mkOption {
      type = attrs;
      default = {};
      description = "Hardware profiles to enable";
    };

    role = mkOption {
      type = attrs;
      default = {};
      description = "Role profiles to enable";
    };

    network = mkOption {
      type = attrs;
      default = {};
      description = "Network profiles to enable";
    };
  };
}
```

**Step 3.2: Create modules/profiles/hardware/default.nix**

```nix
# modules/profiles/hardware/default.nix --- Hardware profiles

{ lib, ... }:

let
  inherit (lib) mkEnableOption mkOption types;
in
{
  options.hardware.profiles = {
    # CPU profiles
    amd = {
      enable = mkEnableOption "AMD CPU optimizations";
      zen = mkEnableOption "Zen CPU specific optimizations";
    };

    intel = {
      enable = mkEnableOption "Intel CPU optimizations";
    };

    # GPU profiles
    nvidia = {
      enable = mkEnableOption "NVIDIA GPU support";
      multiGpu = mkEnableOption "Multi-GPU configuration";
    };

    amdgpu = {
      enable = mkEnableOption "AMD GPU support";
    };

    # Other hardware
    corsair = {
      enable = mkEnableOption "Corsair hardware (AIO, RGB)";
    };

    monitoring = {
      enable = mkEnableOption "Hardware monitoring (lm-sensors)";
    };
  };
}
```

**Step 3.3: Create modules/profiles/hardware/cpu.nix**

```nix
# modules/profiles/hardware/cpu.nix --- CPU profile configurations

{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.profiles;
in
{
  config = lib.mkMerge [
    (lib.mkIf cfg.amd.enable {
      boot.kernelParams = ["amd_iommu=on" "iommu=pt"];

      # AMD CPU optimizations
      hardware.cpu.amd.updateMicrocode = lib.mkDefault true;
    })

    (lib.mkIf cfg.amd.zen {
      # Zen-specific optimizations
      boot.kernelParams = [
        "split_lock_detect=off"
        "threadirqs"
        "preempt=full"
      ];
    })

    (lib.mkIf cfg.intel.enable {
      boot.kernelParams = ["intel_iommu=on" "iommu=pt"];

      # Intel CPU optimizations
      hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
    })
  ];
}
```

**Step 3.4: Create modules/profiles/hardware/gpu.nix**

```nix
# modules/profiles/hardware/gpu.nix --- GPU profile configurations

{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.profiles;
in
{
  config = lib.mkMerge [
    (lib.mkIf cfg.nvidia.enable {
      # Enable NVIDIA support
      hardware.nvidia-common.enable = true;

      boot.kernelModules = ["nvidia" "nvidia_uvm" "nvidia_drm" "nvidia_modeset"];

      lib.mkIf cfg.nvidia.multiGpu {
        # Multi-GPU unified memory settings
        environment.sessionVariables = {
          CUDA_VISIBLE_DEVICES = "0,1";
          NCCL_P2P_LEVEL = "2";
          NCCL_P2P_DISABLE = "0";
          NCCL_IB_DISABLE = "1";
          NCCL_ALGO = "Tree";
        };
      };
    })

    (lib.mkIf cfg.amdgpu.enable {
      # Enable AMDGPU support
      hardware.amdgpu = {
        enable = true;
        opencl.enable = true;
      };

      boot.kernelModules = ["amdgpu"];
      boot.initrd.kernelModules = ["amdgpu"];

      lib.mkIf cfg.amdgpu.wayland {
        # AMDGPU Wayland optimizations
        environment.sessionVariables = {
          ROC_ENABLE_PRE_VEGA = "1";
        };
      };
    })

    (lib.mkIf cfg.corsair.enable {
      # Corsair hardware support
      hardware.corsair.enable = true;
      hardware.corsair.aio.enable = true;
      hardware.corsair.rgb.enable = true;
    })

    (lib.mkIf cfg.monitoring.enable {
      # Hardware monitoring
      hardware.monitoring.enable = true;
    })
  ];
}
```

**Step 3.5: Create modules/profiles/role/default.nix**

```nix
# modules/profiles/role/default.nix --- Role profiles

{ lib, ... }:

let
  inherit (lib) mkEnableOption mkOption types;
in
{
  options.profiles.role = {
    workstation = mkEnableOption "Workstation profile (desktop + development)";
    server = mkEnableOption "Server profile (minimal desktop)";
    mining = mkEnableOption "Mining profile (GPU/CPU mining)";
    gaming = mkEnableOption "Gaming profile (Steam, Lutris, etc.)";
    vr = mkEnableOption "VR profile (WiVRn, SteamVR)";
    desktop = mkEnableOption "Desktop profile (Plasma, Wayland)";
  };
}
```

**Step 3.6: Create modules/profiles/role/implementations.nix**

```nix
# modules/profiles/role/implementations.nix --- Role profile implementations

{ config, lib, ... }:

let
  cfg = config.profiles.role;
in
{
  config = lib.mkMerge [
    (lib.mkIf cfg.workstation {
      # Workstation: full desktop + dev tools
      services.gaming.enable = true;
    })

    (lib.mkIf cfg.desktop {
      # Desktop: Plasma Wayland
      services.desktop.plasma6.enable = true;
    })

    (lib.mkIf cfg.gaming {
      # Gaming: Steam, Lutris, etc.
      services.gaming.enable = true;
    })

    (lib.mkIf cfg.vr {
      # VR: WiVRn
      services.gaming.vr.enable = true;
    })

    (lib.mkIf cfg.mining {
      # Mining: enable mining service
      services.mining.enable = true;
    })
  ];
}
```

**Step 3.7: Create modules/profiles/network/default.nix**

```nix
# modules/profiles/network/default.nix --- Network profiles

{ config, lib, ... }:

let
  clusterHosts = config.networking.cluster.hosts or {};
in
{
  options.profiles.network = with lib.types; {
    tailscale = {
      enable = mkEnableOption "Tailscale VPN";
      advertiseRoutes = mkOption {
        type = listOf str;
        default = [];
        description = "Routes to advertise on Tailscale";
      };
    };
  };

  config = lib.mkIf config.profiles.network.tailscale.enable {
    services.tailscale.enable = true;

    systemd.services.tailscaled.environment = lib.mkMerge [
      (lib.mkIf (config.profiles.network.tailscale.advertiseRoutes != []) {
        TS_ADVERTISE_ROUTES = builtins.concatStringsSep " " config.profiles.network.tailscale.advertiseRoutes;
      })
      { TS_SSH = "true"; }
    ];
  };
}
```

**Step 3.8: Update modules/default.nix to import profiles**

Modify `modules/default.nix` - add to imports:

```nix
imports = [
  # ... existing imports ...

  # Profile system
  ./profiles/default.nix
];
```

**Step 3.9: Commit**

```bash
git add modules/profiles/
git commit -m "refactor(profiles): Add hardware, role, and network profile system"
```

---

## Phase 4: Extract Shell Scripts

### Task 4: Create Scripts Directory and Extract Embedded Scripts

**Files:**
- Create: `scripts/hardware/`
- Create: `scripts/hardware/fan-set.sh`
- Create: `scripts/hardware/fan-get.sh`
- Create: `scripts/hardware/temp-get.sh`
- Create: `scripts/hardware/sys-mon.sh`
- Create: `scripts/hardware/aio-status.sh`
- Create: `scripts/hardware/corsair-rgb.sh`

**Step 4.1: Create scripts/hardware/fan-set.sh**

```bash
#!/usr/bin/env bash
# fan-set --- Set fan speed (0-255) for a specific fan
# Usage: fan-set <fan_number> <pwm_value>
# Example: fan-set 1 128 (sets fan 1 to 50%)

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: fan-set <fan_number> <pwm_value (0-255)>"
  echo "Example: fan-set 1 128  # Set fan 1 to 50%"
  exit 1
fi

fan=$1
pwm=$2
pwm_file="/sys/class/hwmon/hwmon6/pwm$fan"

if [ ! -w "$pwm_file" ]; then
  echo "Error: Cannot write to $pwm_file"
  echo "You may need to disable BIOS fan control first"
  exit 1
fi

echo "$pwm" > "$pwm_file"
echo "Set fan $fan to PWM $pwm ($(awk "BEGIN {printf \"%.0f\", $pwm/255*100}")%)"
```

**Step 4.2: Create scripts/hardware/fan-get.sh**

```bash
#!/usr/bin/env bash
# fan-get --- Get current fan speed and PWM for all fans

set -euo pipefail

echo "Fan Status for MSI X570 TOMAHAWK:"
echo "────────────────────────────────────────"

for i in 1 2 3 4 5 6 7; do
  pwm_file="/sys/class/hwmon/hwmon6/pwm$i"
  rpm_file="/sys/class/hwmon/hwmon6/fan${i}_input"
  label_file="/sys/class/hwmon/hwmon6/fan${i}_label"

  if [ -f "$pwm_file" ]; then
    pwm=$(cat "$pwm_file" 2>/dev/null || echo "N/A")
    rpm=$(cat "$rpm_file" 2>/dev/null || echo "0")
    label="Fan $i"
    [ -f "$label_file" ] && label=$(cat "$label_file")
    percent=$(awk "BEGIN {printf \"%.0f\", $pwm/255*100}")
    printf "%-12s: %4d RPM  PWM: %3d (%3s%%)\n" "$label" "$rpm" "$pwm" "$percent"
  fi
done
```

**Step 4.3: Create scripts/hardware/temp-get.sh**

```bash
#!/usr/bin/env bash
# temp-get --- Get all temperature readings

set -euo pipefail

echo "Temperature Readings:"
echo "────────────────────"

# AMD CPU temps
echo "AMD CPU (k10temp):"
${pkgs.lm_sensors}/bin/sensors -j k10temp-pci-00c3 2>/dev/null | ${pkgs.jq}/bin/jq -r 'to_entries[] | "  \(.key): \(.value.value // .value | tonumber | floor)°C"' 2>/dev/null || ${pkgs.lm_sensors}/bin/sensors k10temp-pci-00c3
echo ""

# Motherboard temps
echo "Motherboard (NCT6775):"
${pkgs.lm_sensors}/bin/sensors -j nct6797-isa-0a20 2>/dev/null | ${pkgs.jq}/bin/jq -r 'to_entries[] | select(.key | contains("temp")) | "  \(.key): \(.value.value // .value | tonumber | floor)°C"' 2>/dev/null || ${pkgs.lm_sensors}/bin/sensors nct6797-isa-0a20 | grep -E "SYSTIN|CPUTIN|TSI"
echo ""

# NVMe temps
echo "NVMe Drives:"
${pkgs.lm_sensors}/bin/sensors -j 2>/dev/null | ${pkgs.jq}/bin/jq -r 'to_entries[] | select(.key | contains("nvme")) | "  \(.key): \(.value["Composite"].value | tonumber | floor)°C"' 2>/dev/null || ${pkgs.lm_sensors}/bin/sensors | grep -A2 nvme
```

**Step 4.4: Create scripts/hardware/sys-mon.sh**

```bash
#!/usr/bin/env bash
# sys-mon --- Comprehensive system monitoring dashboard
# This script aggregates all hardware monitoring information

set -euo pipefail

exec /etc/nixos/scripts/monitor-sensors.sh
```

**Step 4.5: Create scripts/hardware/aio-status.sh**

```bash
#!/usr/bin/env bash
# aio-status --- Corsair AIO cooler status

set -euo pipefail

exec /etc/nixos/scripts/corsair-status.sh
```

**Step 4.6: Create scripts/hardware/corsair-rgb.sh**

```bash
#!/usr/bin/env bash
# corsair-rgb --- Start OpenRGB GUI for Corsair RGB control

set -euo pipefail

exec /etc/nixos/scripts/corsair-rgb
```

**Step 4.7: Make scripts executable**

```bash
chmod +x scripts/hardware/*.sh
ls -l scripts/hardware/
```
Expected: All scripts show -rwxr-xr-x permissions

**Step 4.8: Commit**

```bash
git add scripts/hardware/
git commit -m "refactor(scripts): Extract hardware monitoring scripts from Nix expressions"
```

---

## Phase 5: Create GPU Power Limit Module

### Task 5: Create GPU Power Management Module

**Files:**
- Create: `modules/hardware/gpu-power-limits.nix`

**Step 5.1: Create modules/hardware/gpu-power-limits.nix**

```nix
# modules/hardware/gpu-power-limits.nix --- GPU power limit management
#
# Provides declarative GPU power limit configuration
# Replaces inline systemd services in host configs

{ config, lib, pkgs, ... }:

let
  cfg = config.hardware.gpuPowerLimits;
in
{
  options.hardware.gpuPowerLimits = with lib.types; {
    enable = mkEnableOption "GPU power limit management";

    gpus = mkOption {
      type = attrsOf (submodule {
        options = {
          id = mkOption {
            type = int;
            description = "GPU ID (as seen in nvidia-smi)";
          };
          powerLimit = mkOption {
            type = int;
            description = "Power limit in watts";
          };
          enable = mkEnableOption "This GPU power limit";
        };
      });
      default = {};
      description = "GPU power limit configurations";
      example = {
        gpu-0 = {
          id = 0;
          powerLimit = 130;
          enable = true;
        };
        gpu-1 = {
          id = 1;
          powerLimit = 250;
          enable = true;
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Generate systemd services for each GPU
    systemd.services = lib.mapAttrs' (name: gpuCfg:
      lib.nameValuePair "gpu-${gpuCfg.id}-power-limit" {
        description = "Set GPU ${gpuCfg.id} power limit to ${toString gpuCfg.powerLimit}W";
        wantedBy = ["multi-user.target"];
        before = ["lolminer-nvidia.service"];
        requiredBy = lib.mkIf config.services.mining.lolminer.nvidia.enable ["lolminer-nvidia.service"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.nvidia-settings}/bin/nvidia-smi -i ${toString gpuCfg.id} -pl ${toString gpuCfg.powerLimit}";
        };
      }
    ) (lib.filterAttrs (_: gpuCfg: gpuCfg.enable) cfg.gpus);
  };
}
```

**Step 5.2: Commit**

```bash
git add modules/hardware/gpu-power-limits.nix
git commit -m "refactor(gpu): Add declarative GPU power limit module"
```

---

## Phase 6: Refactor flake.nix

### Task 6: Update flake.nix with mkFlake Pattern

**Files:**
- Modify: `flake.nix`

**Step 6.1: Backup current flake.nix**

```bash
cp flake.nix flake.nix.backup
```

**Step 6.2: Replace flake.nix with mkFlake pattern**

```nix
# flake.nix --- NixOS configuration with mkFlake pattern
#
# Refactored to hlissner style with custom library and profile system

{
  description = "NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    aagl = {
      url = "github:ezKEa/aagl-gtk-on-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-native = {
      url = "github:ryoppippi/claude-code-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs-xr = {
      url = "github:nix-community/nixpkgs-xr";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    scopebuddy = {
      url = "github:OpenGamingCollective/ScopeBuddy";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixcord = {
      url = "github:FlameFlag/nixcord";
    };
    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    home-manager,
    aagl,
    nur,
    claude-native,
    agenix,
    colmena,
    ...
  }: let
    # ========================================================================
    # CUSTOM LIBRARY
    # ========================================================================
    args = {
      inherit self;
      inherit (nixpkgs) lib;
      pkgs = import nixpkgs {};
    };
    lib = import ./lib args;

    # ========================================================================
    # HOST DEFINITIONS (Single source of truth)
    # ========================================================================
    hosts = {
      zephyr = {
        hostName = "zephyr";
        description = "Master Workstation - 32 cores, RTX 3090";
      };
      nexus = {
        hostName = "nexus";
        description = "Build/AIStor Server - 24 cores, 2x RTX 3060 Ti";
      };
      forge = {
        hostName = "forge";
        description = "GPU Mining - 6 cores, 2x RTX 4060 + 2x RX 5700 XT";
      };
      sentry = {
        hostName = "sentry";
        description = "Monitoring Server - 16 cores, RX 5600 XT";
      };
    };

    # ========================================================================
    # HELPER FUNCTIONS
    # ========================================================================

    # Common modules shared across all hosts
    commonModules = [
      home-manager.nixosModules.home-manager
      aagl.nixosModules.default
      nur.modules.nixos.default
      agenix.nixosModules.default
      ./modules/default.nix
      {nixpkgs.overlays = [self.overlays.default];}
    ];

    # Create NixOS system configuration
    mkNixosSystem = {
      hostName,
      extraModules ? [],
    }:
      nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = {inherit inputs;};
        modules =
          commonModules
          ++ [
            ./hosts/${hostName}/configuration.nix
          ]
          ++ extraModules;
      };
  in {
    # ========================================================================
    # OUTPUT 1: nixosConfigurations
    # ========================================================================
    nixosConfigurations =
      builtins.mapAttrs
      (_name: value: mkNixosSystem {inherit (value) hostName;})
      hosts;

    # ========================================================================
    # OUTPUT 2: colmena
    # ========================================================================
    colmena = import ./colmena.nix {
      inherit inputs self;
      inherit hosts;
    };

    # ========================================================================
    # OUTPUT 3: colmenaHive
    # ========================================================================
    colmenaHive = colmena.lib.makeHive self.outputs.colmena;

    # ========================================================================
    # OUTPUT 4: packages
    # ========================================================================
    packages.x86_64-linux.claude = claude-native.packages.x86_64-linux.claude;

    # ========================================================================
    # OUTPUT 5: overlays
    # ========================================================================
    overlays.default = import ./overlay.nix;

    # ========================================================================
    # OUTPUT 6: apps
    # ========================================================================
    apps.x86_64-linux.colmena = {
      type = "app";
      program = "${colmena.packages.x86_64-linux.colmena}/bin/colmena";
    };
  };
}
```

**Step 6.3: Verify flake.nix syntax**

```bash
nix flake check
```
Expected: Success

**Step 6.4: Test build**

```bash
sudo nixos-rebuild build --flake .#zephyr
```
Expected: Build succeeds

**Step 6.5: Commit**

```bash
git add flake.nix flake.nix.backup
git commit -m "refactor(flake): Refactor to mkFlake pattern with custom library"
```

---

## Phase 7: Refactor Host Configs

### Task 7: Refactor zephyr Host Config

**Files:**
- Modify: `hosts/zephyr/configuration.nix`

**Step 7.1: Refactor hosts/zephyr/configuration.nix**

Replace the 400+ line file with profile-based composition:

```nix
# Zephyr Host Configuration
# RTX 3090, Quest Pro, 4K HDR TV
# Master Workstation - 32 cores, RTX 3090

{pkgs, inputs, ...}: {
  imports = [
    ./monitoring.nix
    ./hardware-configuration.nix
    ../../modules/default.nix
  ];

  # ============================================================================
  # HOST IDENTIFICATION
  # ============================================================================
  networking.hostName = "zephyr";

  # ============================================================================
  # PROFILES (Declarative composition)
  # ============================================================================
  hardware.profiles = {
    nvidia.enable = true;
    nvidia.multiGpu = true;
    corsair.enable = true;
    monitoring.enable = true;
  };

  profiles.role = {
    workstation = true;
    gaming = true;
    vr = true;
  };

  profiles.network.tailscale = {
    enable = true;
    advertiseRoutes = ["10.1.1.0/24"];
  };

  # ============================================================================
  # GPU POWER LIMITS (Declarative)
  # ============================================================================
  hardware.gpuPowerLimits = {
    enable = true;
    gpus = {
      gpu-0 = {id = 0; powerLimit = 130; enable = true;};
      gpu-1 = {id = 1; powerLimit = 250; enable = true;};
    };
  };

  # ============================================================================
  # BOOTLOADER & KERNEL
  # ============================================================================
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_zen;

  boot.kernelParams = [
    "split_lock_detect=off"
    "threadirqs"
    "preempt=full"
    "processor.max_cstate=1"
    "intel_idle.max_cstate=1"
    "iommu=pt"
  ];

  boot.kernelModules = [
    "nvidia" "nvidia_uvm" "nvidia_drm" "nvidia_modeset"
  ];

  # ============================================================================
  # NETWORKING
  # ============================================================================
  networking.networkmanager.enable = true;
  networking.networkmanager.dns = "none";
  networking.wireless.enable = true;
  hardware.bluetooth.enable = true;

  services.unbound-cluster.enable = true;
  networking.cluster-hosts = {
    enable = true;
    populateLocal = true;
  };

  # ============================================================================
  # AI SERVICES
  # ============================================================================
  programs.scopebuddy = {
    enable = true;
    autoDetect = {
      resolution = true;
      hdr = true;
      vrr = true;
    };
  };

  programs.anime-game-launcher.enable = true;
  programs.sleepy-launcher.enable = true;
  programs.honkers-railway-launcher.enable = true;
  programs.wavey-launcher.enable = true;

  programs.lm-studio.enable = true;
  programs.stability-matrix.enable = true;

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    dockerSocket.enable = true;
  };

  services.spacebot = {
    enable = true;
    useGateway = true;
    gatewayUrl = "http://127.0.0.1:8080";
    host = "127.0.0.1";
    port = 19898;
    memory = "4G";
    cpu = "2";
    providerKeys = {
      ZAI_CODING_PLAN_KEY = "/run/agenix/zai-api-key";
      KILO_API_KEY = "/run/agenix/kilo-api-key";
    };
    discord.enable = false;
  };

  age.identityPaths = ["/home/j_kro/.age/key.txt"];

  age.secrets = {
    lm-studio-api-key = {
      file = "${inputs.self}/secrets/lm-studio-api-key.age";
      mode = "440";
      owner = "ai-inference";
      group = "ai-inference";
    };
    huggingface-token = {
      file = "${inputs.self}/secrets/huggingface-token.age";
      mode = "440";
      owner = "j_kro";
      group = "users";
    };
    zai-api-key = {
      file = "${inputs.self}/secrets/zai-api-key.age";
      mode = "440";
      owner = "j_kro";
      group = "ai-inference";
    };
    kilo-api-key = {
      file = "${inputs.self}/secrets/kilo-api-key.age";
      mode = "440";
      owner = "j_kro";
      group = "users";
    };
  };

  services.redis.servers."" .enable = true;

  # ============================================================================
  # AI INFERENCE GATEWAY
  # ============================================================================
  services.ai-inference = {
    enable = true;
    backend = {
      url = "http://127.0.0.1:1234";
      type = "lm-studio";
      lmStudio.apiKeyFile = "/run/agenix/lm-studio-api-key";
      zai = {
        enable = true;
        apiKeyFile = "/run/agenix/zai-api-key";
        baseUrl = "https://api.z.ai/api/coding/paas/v4";
      };
    };
    gateway = {
      enable = true;
      host = "127.0.0.1";
      port = 8080;
      workers = 1;
    };
    routing = {
      enable = true;
      defaultModel = "magnum-opus-35b-a3b-i1";
      fallbackChain = ["vllm" "lm-studio" "zai"];
    };
    auth.mode = "none";
    monitoring.enable = true;
    rateLimit.enable = false;
    mcp = {
      enable = true;
      servers = {
        web-search-prime = {
          url = "https://api.z.ai/api/mcp/web_search_prime/mcp";
          headers.Authorization = "Bearer /run/agenix/zai-api-key";
        };
        web-reader = {
          url = "https://api.z.ai/api/mcp/web_reader/mcp";
          headers.Authorization = "Bearer /run/agenix/zai-api-key";
        };
        zread = {
          url = "https://api.z.ai/api/mcp/zread/mcp";
          headers.Authorization = "Bearer /run/agenix/zai-api-key";
        };
        "4-5v-mcp-server" = {
          url = "https://api.z.ai/api/mcp/4_5v/mcp";
          headers.Authorization = "Bearer /run/agenix/zai-api-key";
        };
      };
    };
    rag = {
      enable = true;
      qdrant.enable = true;
      qdrant.memoryLimit = "4G";
    };
  };

  services.mcp-servers = {
    enable = true;
    servers.playwright.enable = true;
  };

  services.mining.enable = true;
  services.multimedia.gstreamer.enable = true;
  services.spotify-spotx.enable = true;
  services.flatpak-kde = {
    enable = true;
    autoUpdate = true;
  };

  services.mining.lolminer.nvidia = {
    enable = true;
    autostart = false;
    devices = "1";
    powerLimit = 250;
    apiPort = 4068;
  };

  services.mining.xmrig = {
    enable = true;
    autostart = false;
    threads = 16;
  };

  services.monitoring.prometheus = {
    enable = true;
    retentionDays = 30;
    scrapeInterval = "15s";
  };
  services.monitoring.grafana.enable = true;

  # ============================================================================
  # FIREWALL
  # ============================================================================
  networking.firewall = {
    allowedTCPPorts = [9757 18789 18790 19898 1234 8080];
    allowedUDPPorts = [9757 9758 9759 27031 27036 5353 9947];
    interfaces."tailscale0".allowedTCPPorts = [18789 18790];
    interfaces."enp38s0".allowedTCPPorts = [111 2049 20048];
    interfaces."enp38s0".allowedUDPPorts = [111 2049 20048];
  };

  # ============================================================================
  # SYSTEM PACKAGES
  # ============================================================================
  environment.systemPackages = with pkgs; [
    # Shell & CLI
    fish starship zoxide fzf eza btop

    # Version control
    tmux mosh git

    # Networking
    tailscale networkmanager dbus-broker slirp4netns podman-compose

    # Deployment
    inputs.colmena.packages.${"x86_64-linux"}.colmena

    # Hardware monitoring scripts
    (pkgs.writeShellScriptBin "fan-set" "exec ${./scripts/hardware/fan-set.sh}")
    (pkgs.writeShellScriptBin "fan-get" "exec ${./scripts/hardware/fan-get.sh}")
    (pkgs.writeShellScriptBin "temp-get" "exec ${./scripts/hardware/temp-get.sh}")
    (pkgs.writeShellScriptBin "sys-mon" "exec ${./scripts/hardware/sys-mon.sh}")
    (pkgs.writeShellScriptBin "aio-status" "exec ${./scripts/hardware/aio-status.sh}")
    (pkgs.writeShellScriptBin "corsair-rgb" "exec ${./scripts/hardware/corsair-rgb.sh}")

    # Network discovery
    nmap netdiscover arp-scan iproute2 iputils dnsutils whois net-tools

    # Development
    nodejs gh jq inputs.claude-native.packages.x86_64-linux.claude

    # AI & ML
    llama-cpp whisper-cpp pipx pkgs.python312Packages.huggingface-hub

    # Mining
    xmrig lolminer

    # Desktop
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.twilight
  ];

  # ============================================================================
  # MULTI-GPU ENVIRONMENT
  # ============================================================================
  environment.sessionVariables = {
    CUDA_VISIBLE_DEVICES = "0,1";
    NCCL_P2P_LEVEL = "2";
    NCCL_P2P_DISABLE = "0";
    NCCL_IB_DISABLE = "1";
    NCCL_ALGO = "Tree";
    GGML_CUDA_ENABLE_UNIFIED_MEMORY = "1";
    GGML_CUDA_GPU_MEMORY_FRACTION = "0.9";
    LLAMA_GRAPH_POOL_SIZE = "0.2";
  };

  # ============================================================================
  # HOME MANAGER (via modules)
  # ============================================================================
  home-manager-browser.enable = true;
  home-manager-discord.enable = true;
  home-manager-services = {
    enable = true;
    hfToken = "/run/agenix/huggingface-token";
  };
  hm-xdg.enable = true;

  # ============================================================================
  # SYSTEM STATE
  # ============================================================================
  system.stateVersion = "26.05";
}
```

**Step 7.2: Update colmena.nix for new structure**

The colmena.nix should already work with the hosts attrset, but verify:

**Step 7.3: Test zephyr config**

```bash
sudo nixos-rebuild test --flake .#zephyr
```
Expected: Build and apply successfully

**Step 7.4: Commit**

```bash
git add hosts/zephyr/configuration.nix
git commit -m "refactor(zephyr): Refactor to profile-based composition"
```

---

## Phase 8: Refactor Remaining Host Configs

### Task 8: Refactor nexus, forge, sentry

**Files:**
- Modify: `hosts/nexus/configuration.nix`
- Modify: `hosts/forge/configuration.nix`
- Modify: `hosts/sentry/configuration.nix`

**Step 8.1: Refactor hosts/nexus/configuration.nix**

Similar pattern to zephyr:

```nix
# Nexus Host Configuration - Build and Backup Node
# 10.1.1.120 - 24 cores, 2x RTX 3060 Ti

{pkgs, ...}: {
  imports = [
    ./monitoring.nix
    ./hardware-configuration.nix
    ../../modules/default.nix
  ];

  networking.hostName = "nexus";

  # Profiles
  hardware.profiles = {
    nvidia.enable = true;
    monitoring.enable = true;
  };

  profiles.role = {
    gaming = true;
    vr = true;
  };

  profiles.network.tailscale.enable = true;

  # ... rest of nexus-specific config
}
```

**Step 8.2: Refactor hosts/forge/configuration.nix**

Focus on mining-only profile:

```nix
# Forge Host Configuration - GPU Mining Rig
# 10.1.1.130 - 6 cores, 2x RTX 4060 + 2x RX 5700 XT

{lib, pkgs, ...}: {
  imports = [
    ./monitoring.nix
    ./hardware-configuration.nix
    ../../modules/default.nix
  ];

  networking.hostName = "forge";

  # Profiles
  hardware.profiles = {
    nvidia.enable = true;
    amdgpu.enable = true;
  };

  profiles.role.mining = true;

  # ... mining-specific config
}
```

**Step 8.3: Refactor hosts/sentry/configuration.nix**

Focus on monitoring server profile:

```nix
# Sentry Host Configuration - Monitoring Server
# 10.1.1.140 - 16 cores, RX 5600 XT

{pkgs, ...}: {
  imports = [
    ./monitoring.nix
    ./hardware-configuration.nix
    ../../modules/default.nix
  ];

  networking.hostName = "sentry";

  # Profiles
  hardware.profiles = {
    amdgpu.enable = true;
    monitoring.enable = true;
  };

  profiles.role.mining = true;  # CPU mining

  profiles.network.tailscale = {
    enable = true;
    advertiseRoutes = ["10.1.1.0/24"];
  };

  # ... sentry-specific config
}
```

**Step 8.4: Test all host configs**

```bash
for host in zephyr nexus forge sentry; do
  echo "Testing $host..."
  sudo nixos-rebuild build --flake .#$host
done
```
Expected: All builds succeed

**Step 8.5: Commit**

```bash
git add hosts/
git commit -m "refactor(hosts): Refactor nexus, forge, sentry to profile-based composition"
```

---

## Phase 9: Final Testing and Documentation

### Task 9: Comprehensive Testing

**Step 9.1: Run flake check**

```bash
nix flake check
```
Expected: Success

**Step 9.2: Test colmena hive**

```bash
colmena eval --evaluator each
```
Expected: All hosts evaluate successfully

**Step 9.3: Create migration documentation**

Create `docs/HLISSNER_STYLE_MIGRATION.md`:

```markdown
# Hlissner-Style Migration Guide

This document describes the refactoring from the original NixOS configuration
to the hlissner/dotfiles-inspired architecture.

## Key Changes

### 1. Custom Library (`lib/`)
- `lib/modules.nix`: Auto-import helpers (mapModules, mapHosts)
- `lib/attrs.nix`: Attribute set utilities
- Reduces boilerplate in flake.nix

### 2. Home Manager Modules (`modules/home-manager/`)
- `browser.nix`: Zen Browser configuration
- `discord.nix`: Vesktop/Nixcord configuration
- `xdg.nix`: XDG compliance enforcement
- `services.nix`: User systemd services

### 3. Profile System (`modules/profiles/`)
- `hardware/`: CPU, GPU, Corsair profiles
- `role/`: Workstation, server, mining, gaming, VR
- `network/`: Tailscale profiles

### 4. Extracted Scripts (`scripts/hardware/`)
- `fan-set.sh`, `fan-get.sh`, `temp-get.sh`
- `sys-mon.sh`, `aio-status.sh`, `corsair-rgb.sh`

### 5. GPU Power Limits Module
- `modules/hardware/gpu-power-limits.nix`
- Declarative GPU power management

## Migration Path

For each host:
1. Replace inline config with profile assignments
2. Move home-manager config to separate modules
3. Use profile system for hardware/role/network

## Benefits

- **DRY**: Single source of truth for hosts (flake.nix hosts attrset)
- **Separation**: System/user configs clearly separated
- **Reusable**: Profiles can be composed across hosts
- **Maintainable**: Smaller, focused files
```

**Step 9.4: Commit**

```bash
git add docs/HLISSNER_STYLE_MIGRATION.md
git commit -m "docs(migration): Add hlissner-style migration guide"
```

**Step 9.5: Create summary document**

Create `docs/plans/2025-03-06-hlissner-style-refactor-SUMMARY.md` with implementation notes and any deviations from the plan.

---

## Post-Implementation Verification

### Final Tests

1. **All hosts build**:
   ```bash
   for host in zephyr nexus forge sentry; do
     sudo nixos-rebuild build --flake .#$host
   done
   ```

2. **Colmena works**:
   ```bash
   colmena apply local --on zephyr --eval-only
   ```

3. **Home Manager configs work**:
   ```bash
   home-manager switch --flake .#j_kro@zephyr
   ```

4. **Scripts accessible**:
   ```bash
   which fan-set fan-get temp-get sys-mon
   ```

---

## Rollback Plan

If issues arise:

```bash
# Revert to original config
git checkout main

# Or rollback specific generation
sudo nixos-rebuild switch --rollback
```

---

**Plan complete and saved to `docs/plans/2025-03-06-hlissner-style-refactor.md`.**

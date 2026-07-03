# Recursively collect NixOS module files from the modules/ directory tree.
#
# Walks the module tree, skipping known non-module directories and files
# (libraries, Home Manager modules, submodules imported via import ./..., etc.).
# Returns a flat list of .nix file paths suitable for use in imports = [...].
#
# Usage in modules/default.nix:
#   imports = import ./lib/collect-modules.nix { inherit lib; basePath = ./.; };
{
  lib,
  basePath,
}: let
  inherit (builtins) readDir hasAttr;
  inherit (lib) hasSuffix;

  # Directories to skip entirely — these are not NixOS modules.
  # This includes Home Manager modules, library helpers, media assets, etc.
  skipDirs = {
    "lib" = true; # Library helpers (e.g. spotify-common.nix)
    "home-manager" = true; # Home Manager modules (imported via system/home-manager.nix)
    "__pycache__" = true; # Python bytecode cache
    "wallpapers" = true; # Desktop wallpaper images
    "patches" = true; # Patch files
    "files" = true; # Non-module assets (e.g. gaming/files/)
    "scripts" = true; # Shell scripts
    "js" = true; # JavaScript runtime files
    "kubernetes" = true; # K8s resource YAML files
    "dashboards" = true; # Grafana dashboard JSON templates (not NixOS modules)
  };

  # Relative paths (from modules/) to exclude.
  # These are .nix files that are NOT NixOS module definitions — they are
  # library files imported via import ./... in a parent module, or helpers
  # that return function sets rather than {options, config} blocks.
  excludeFiles = {
    "default.nix" = true; # This file itself — circular import prevention
    "desktop/lib/spotify-common.nix" = true; # Library: returns function set
    "services/monitoring/dashboards/lib.nix" = true; # Library: returns Grafana dashboard helpers
    "development/ai-coding-tools/claude.nix" = true; # Submodule: imported by parent
    "development/ai-coding-tools/crush.nix" = true; # Submodule: imported by parent
    "development/ai-coding-tools/droid.nix" = true; # Submodule: imported by parent
    "development/ai-coding-tools/mcp-defs.nix" = true; # Submodule: imported by parent
    "development/ai-coding-tools/omp.nix" = true; # Submodule: imported by parent
    "development/ai-coding-tools/opencode.nix" = true; # Submodule: imported by parent
    "development/ai-coding-tools/pi.nix" = true; # Submodule: imported by parent

    "profiles/networking.nix" = true; # Library: returns mkNetworkingConfig function
    "system/network.nix" = true; # Dead code: references missing config.cluster.config
    "system/ssh-autodiscover.nix" = true; # Dead code: references missing config.cluster.config

    # Profile subdirectory default.nix files:
    # These are already imported as directories by profiles/default.nix (e.g. ./role -> role/default.nix).
    # The NixOS module system doesn't deduplicate directory vs file paths, so exclude to avoid double-declaration.
    "profiles/hardware/default.nix" = true;
    "profiles/role/default.nix" = true;
    "profiles/network/default.nix" = true;
    "port-helpers.nix" = true; # Library: helper functions, NOT a NixOS module
    "services/oauth2-proxy-config.nix" = true; # Library: shared oauth2 config data, NOT a module
    "services/hermes-moa.nix" = true; # Library: declarative MoA config, NOT a standalone NixOS module
    # implementations.nix files are imported by their respective subdirectory default.nix, and can be
    # safely collected here too (file path dedup works when both refs are file paths).
  };

  # Recursively walk the directory tree, collecting .nix file paths.
  # dir    — absolute path to the current directory (e.g. /etc/nixos/modules/system)
  # prefix — relative path prefix for exclusion matching (e.g. "system/")
  walk = dir: prefix: let
    entries = readDir dir;
    names = builtins.attrNames entries;
  in
    builtins.foldl' (
      acc: name: let
        path = dir + "/${name}";
        rel = prefix + name;
      in
        if entries.${name} == "directory"
        then
          # Recurse into subdirectories unless skipped
          if hasAttr name skipDirs
          then acc
          else acc ++ walk path "${rel}/"
        else if hasSuffix ".nix" name && !hasAttr rel excludeFiles
        then
          # Include .nix files that aren't in the exclusion list
          acc ++ [path]
        else acc
    ) []
    names;
in
  walk basePath ""

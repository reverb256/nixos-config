# Unified Autoupdate Module
#
# Governs all automated version bumps across the cluster via a single
# declarative interface. Replace scattered bump workflows with one
# SPOC-style config.
#
# Usage:
#   services.unified-autoupdate = {
#     enable = true;
#     schedule = "*-*-* 06:00:00";
#     programs = {
#       peakminer = {
#         github = "peakminer/peakminer";
#         nixPkg = "pkgs/peakminer.nix";
#         bumpScript = "scripts/peakminer-bump.py";
#         commit = true;
#       };
#       hermes-agent = {
#         github = "NousResearch/hermes-agent";
#         nixProfile = true;
#         hosts = ["j_kro@10.1.1.110" "j_kro@10.1.1.120" "j_kro@10.1.1.130" "j_kro@10.1.1.140"];
#       };
#     };
#   };

{ config, lib, pkgs, ... }:

let
  cfg = config.services.unified-autoupdate;

  inherit
    (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  # Programs config JSON — generated from Nix options at build time
  programsConfig = pkgs.writeText "unified-bump-programs.json" (builtins.toJSON {
    programs = lib.mapAttrsToList (name: program: {
      name = name;
      github = program.github;
      type = if program.nixPkg != null then "nix-pkg"
             else if program.nixProfile then "nix-profile"
             else "systemd-service";
      nixPkg = program.nixPkg;
      bumpScript = program.bumpScript;
      commit = program.commit;
      hosts = program.hosts;
    }) cfg.programs;
  });

  # The bump script (external file to avoid Nix string-escaping issues)
  bumpScript = pkgs.writeShellScriptBin "unified-bump"
    (builtins.readFile ./unified-bump.sh);

  resolvedConfigFile = if cfg.configFile != null
    then cfg.configFile
    else toString programsConfig;

in {
  options.services.unified-autoupdate = {
    enable = mkEnableOption "Unified auto-update for all cluster programs";

    schedule = mkOption {
      type = types.str;
      default = "*-*-* 06:00:00";
      description = "systemd calendar expression for update check schedule.";
    };

    configFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to a JSON file describing programs to track.
        If null, uses the generated config from the `programs` option.
      '';
    };

    stateFile = mkOption {
      type = types.path;
      default = "/var/lib/unified-autoupdate/state.json";
      description = "Path where last-checked versions are stored.";
    };

    logFile = mkOption {
      type = types.path;
      default = "/var/log/unified-autoupdate.log";
      description = "Path where update logs are written.";
    };

    programs = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          github = mkOption {
            type = types.str;
            description = "GitHub repository in owner/repo format.";
          };

          nixPkg = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Path to the Nix package file to bump (relative to repo root).";
          };

          bumpScript = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Path to a dedicated bump script (relative to repo root).";
          };

          commit = mkOption {
            type = types.bool;
            default = false;
            description = "Auto-commit and push the bumped file.";
          };

          nixProfile = mkOption {
            type = types.bool;
            default = false;
            description = "Upgrade via nix profile instead of editing a file.";
          };

          hosts = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "SSH targets to upgrade (nix-profile type only).";
          };
        };
      });
      default = {};
      description = "Map of programs to auto-update.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.unified-autoupdate = {
      description = "Unified autoupdate check";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      script = ''
        # Copy generated programs config if using auto-generated
        ${pkgs.coreutils}/bin/cp ${resolvedConfigFile} ${cfg.stateFile}.programs.json
        ${bumpScript}/bin/unified-bump \
          "${cfg.stateFile}" \
          "${cfg.stateFile}.programs.json" \
          "${cfg.logFile}"
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ReadWritePaths = [
          "/var/lib/unified-autoupdate"
          "/var/log"
          "/home/j_kro/Projects/nixos-config"
        ];
      };
    };

    systemd.timers.unified-autoupdate = {
      description = "Unified autoupdate timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "5min";
      };
    };

    system.activationScripts.unified-autoupdate = ''
      mkdir -p /var/lib/unified-autoupdate
      touch ${cfg.logFile}
      chmod 644 ${cfg.logFile}
    '';
  };
}

# Hermes Agent — Declarative NixOS Module
#
# SPOC for all Hermes profile, skill, bundle, cron, and gateway config.
# Everything that was imperatively set up in ~/.hermes/ is declared here
# and deployed via `git commit` + `colmena deploy`.
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkIf mkOption types;

  cfg = config.services.hermes;
  user = "j_kro";
  hermesHome = "/home/${user}/.hermes";
in {
  options.services.hermes = {
    default = mkOption {
      type = types.attrs;
      default = {};
      description = "Default profile configuration (set by Hermes flake)";
      internal = true;
    };
    enable = mkEnableOption "Hermes Agent declarative management";

    profiles = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          enable = mkEnableOption "this Hermes profile";
          soul = mkOption {
            type = types.lines;
            description = "SOUL.md personality for this profile";
          };
          skills = mkOption {
            type = types.listOf types.str;
            default = [];
            description = "Skills to load in skills.default for this profile";
          };
          model = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Default model for this profile (null = inherit main)";
          };
          provider = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Default provider for this profile";
          };
          description = mkOption {
            type = types.str;
            default = "";
            description = "Kanban orchestrator description";
          };
        };
      });
      default = {};
      description = "Declared Hermes profiles with SOUL.md and config";
    };

    skills = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          enable = mkEnableOption "this skill";
          content = mkOption {
            type = types.lines;
            description = "Full SKILL.md content (YAML frontmatter + body)";
          };
          category = mkOption {
            type = types.str;
            default = "infrastructure";
            description = "Skill category folder";
          };
        };
      });
      default = {};
      description = "Custom skills installed into ~/.hermes/skills/";
    };

    bundles = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          enable = mkEnableOption "this bundle";
          skills = mkOption {
            type = types.listOf types.str;
            description = "Skills in this bundle";
          };
          description = mkOption {
            type = types.str;
            default = "";
            description = "Bundle description";
          };
        };
      });
      default = {};
      description = "Skill bundles (/command groups)";
    };

    taps = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Skill source taps (e.g. mattpocock/skills)";
    };

    gateway = {
      multiplexProfiles = mkOption {
        type = types.bool;
        default = false;
        description = "Enable gateway multiplex_profiles";
      };
      profileRoutes = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            platform = mkOption {type = types.str;};
            chatId = mkOption {
              type = types.nullOr types.str;
              default = null;
            };
            guildId = mkOption {
              type = types.nullOr types.str;
              default = null;
            };
            profile = mkOption {type = types.str;};
          };
        });
        default = {};
        description = "Channel->profile route map";
      };
    };

    cron = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          enable = mkEnableOption "this cron job";
          schedule = mkOption {
            type = types.str;
            description = "Cron expression";
          };
          skill = mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          prompt = mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          deliver = mkOption {
            type = types.str;
            default = "origin";
            description = "Delivery target: origin, local, telegram, etc.";
          };
        };
      });
      default = {};
      description = "Scheduled cron jobs";
    };
  };

  imports = [
    ./config.nix
    ./data.nix
  ];
}

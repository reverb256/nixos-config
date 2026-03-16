{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.services.hermes-agent;
  hermesPackage = import ./package.nix { inherit pkgs lib config; };
in
{
  options.services.hermes-agent = {
    enable = lib.mkEnableOption "Hermes Agent - self-improving AI agent";

    packageSrc = lib.mkOption {
      type = lib.types.path;
      default = inputs.hermes-agent;
      defaultText = "inputs.hermes-agent";
      description = "Hermes agent source";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "hermes";
      description = "User account for Hermes Agent";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "hermes";
      description = "Group for Hermes Agent";
    };

    sharedStorage = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable NFS shared storage for skills/memory";
      };

      mountPoint = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/hermes";
        description = "Mount point for shared Hermes data";
      };

      nfsServer = lib.mkOption {
        type = lib.types.str;
        example = "10.1.1.120";
        description = "NFS server address";
      };

      nfsPath = lib.mkOption {
        type = lib.types.str;
        example = "/mnt/garage/hermes";
        description = "NFS export path";
      };
    };

    aiGateway = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Connect to local AI Inference Gateway";
      };

      url = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:8080/v1";
        description = "AI Gateway URL (OpenAI-compatible)";
      };
    };

    terminal = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable terminal tool access";
      };

      requireApproval = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Require user approval for terminal commands";
      };

      allowedCommands = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.str);
        default = null;
        description = "Allow-list of commands (null = allow all)";
      };
    };

    customSkills = lib.mkOption {
      type = lib.types.path;
      default = ./skills;
      defaultText = "./skills";
      description = "Path to custom NixOS-specific skills";
    };
  };
}

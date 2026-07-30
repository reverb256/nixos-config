{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.programs.gitlawb;
  inherit (lib) mkEnableOption mkIf mkOption types;
  gitlawbPkgs = inputs.gitlawb.packages.${pkgs.stdenv.system};
in {
  options.programs.gitlawb = {
    enable = mkEnableOption "gitlawb CLI + git remote helper";
    package = mkOption {
      type = types.package;
      default = gitlawbPkgs.default;
      description = "gitlawb CLI package set providing gl, git-remote-gitlawb, gitlawb-node";
    };
    nodePackage = mkOption {
      type = types.package;
      default = gitlawbPkgs.gitlawb-node;
      description = "gitlawb-node server package";
    };
    gitRemote = {
      did = mkOption {
        type = types.str;
        default = "did:key:z6MkgMv7QQEKKv2fKMrzQBEctxadgqxugUocWeEcBuXvomLo";
        description = "DID root used for the gitlawb remote URL";
      };
      repo = mkOption {
        type = types.str;
        default = "nixos";
        description = "Repository path under the DID root";
      };
      extraRemotes = mkOption {
        type = types.listOf (types.attrsOf types.str);
        default = [ ];
        description = "Additional remotes to add, as name→url attrsets";
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package cfg.nodePackage ];

    programs.git = {
      enable = true;
      extraConfig = {
        "remote \"gitlawb\"".url = "gitlawb://${cfg.gitRemote.did}/${cfg.gitRemote.repo}";
      } // lib.listToAttrs (
        lib.imap0 (i: remote:
          { name = "remote \"${remote.name}\"."; value = { url = remote.url; }; }
        ) cfg.gitRemote.extraRemotes
      );
    };
  };
}

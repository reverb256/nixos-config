{ config, lib, ... }:
let
  c = config.lib.stylix.colors.withHashtag or {};
  inherit (lib) mkIf;
in mkIf (config.stylix.enable or false) {
  programs.lazygit = {
    enable = true;
    settings = {
      gui = {
        showIcons = true;
        theme = {
          activeBorderColor = [ (c.base0D or "#00ffff") "bold" ];
          cherryPickedCommitBgStyle = [ (c.base0B or "#00ffff") ];
          unstagedChangesStyle = [ (c.base08 or "#ff0000") ];
        };
      };
      git = {
        paging.pager = "delta --dark --paging=never";
        autoFetch = true;
        autoStageResolvedConflicts = true;
      };
    };
  };
}

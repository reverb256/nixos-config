_: {
  programs.lazygit = {
    enable = true;
    settings = {
      gui = {
        showIcons = true;
        theme = {
          activeBorderColor = ["cyan" "bold"];
          cherryPickedCommitBgStyle = ["cyan"];
          unstagedChangesStyle = ["red"];
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

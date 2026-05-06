{
  pkgs,
  lib,
  ...
}: {
  programs.git = {
    enable = true;
    userName = "reverb256";
    userEmail = "j_kroeker@reverb256.ca";

    delta = {
      enable = true;
      options = {
        navigate = true;
        side-by-side = true;
        line-numbers = true;
      };
    };

    lfs.enable = true;

    extraConfig = {
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      pull.rebase = true;
      rerere.enabled = true;
      core.pager = "delta";
      merge.conflictstyle = "diff3";
    };
  };

  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
      prompt = "enabled";
    };
  };
}

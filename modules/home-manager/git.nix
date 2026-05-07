{
  pkgs,
  lib,
  ...
}: {
  programs.git = {
    enable = true;

    settings = {
      user.name = "reverb256";
      user.email = "j_kroeker@reverb256.ca";
      init.defaultBranch = "main";
      push.autoSetupRemote = true;
      pull.rebase = true;
      rerere.enabled = true;
      core.pager = "delta";
      merge.conflictstyle = "diff3";
    };

    lfs.enable = true;
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      side-by-side = true;
      line-numbers = true;
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

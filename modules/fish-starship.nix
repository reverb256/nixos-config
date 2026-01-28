_: {
  config = {
    # Fish Shell Configuration
    programs.fish = {
      enable = true;
      shellAliases = {
        # Navigation aliases
        ".." = "cd ..";
        "..." = "cd ../..";
        "...." = "cd ../../..";
        "....." = "cd ../../../..";
      };
    };
  };
}

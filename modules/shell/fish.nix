# Fish Shell Configuration
{ config, lib, pkgs, ... }:
{
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      # Initialize zoxide for smart cd
      if type -q zoxide
        zoxide init fish | source
      end

      # Set greeting to empty
      set -g fish_greeting ""

      # Hugging Face CLI - symlink agenix secret to expected HF token path
      set -l hf_token_dir "$HOME/.cache/huggingface"
      set -l hf_token_file "$hf_token_dir/token"

      if test -r /run/agenix/huggingface-token
        mkdir -p $hf_token_dir
        ln -sf /run/agenix/huggingface-token $hf_token_file
      end
    '';
    shellAliases = {
      # List aliases - modern replacements
      ll = "eza -lh --group-directories-first --icons=auto";
      la = "eza -la --group-directories-first --icons=auto";
      l = "eza --group-directories-first --icons=auto";
      lt = "eza --tree --level=2 --long --icons --git";

      # File viewing aliases - modern replacements
      cat = "bat --paging=always";
      less = "bat --paging=always";
      more = "bat --paging=always";

      # Process monitoring
      top = "btop";
      htop = "btop";

      # Search aliases - modern replacements
      grep = "rg";
      find = "fd";
      locate = "fd";

      # Diff viewing
      diff = "delta";

      # Disk usage
      du = "dust";
      df = "duf";

      # JSON/YAML processing
      jq = "jq";  # Already jq, keeping for consistency

      # Editor aliases
      vi = "nvim";
      vim = "nvim";
      ex = "nvim";
      view = "nvim -R";

      # Git aliases
      g = "git";
      gs = "git status";
      gc = "git commit";
      gp = "git push";
      gl = "git log --oneline -10";
      lg = "lazygit";

      # Build tool aliases
      make = "just";

      # Directory navigation (zoxide)
      cd = "z";

      # NixOS aliases
      update = "sudo nixos-rebuild switch --flake /etc/nixos";
      build = "sudo nixos-rebuild build --flake /etc/nixos";
      try = "sudo nixos-rebuild test --flake /etc/nixos";

      # AI/LLM aliases
      lms = "~/.lmstudio/bin/lms";
    };
  };
}

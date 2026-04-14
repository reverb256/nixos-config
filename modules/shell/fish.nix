{pkgs, ...}: {
  programs.fish = {
    enable = true;

    interactiveShellInit = ''
      set -gx TZ America/Winnipeg
    '';
  };

  environment.systemPackages = with pkgs; [
    fish

    zoxide

    fzf

    lazydocker
    podman-compose
  ];
}

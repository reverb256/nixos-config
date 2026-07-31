{ config, lib, pkgs, inputs, hostName, vfioPkgs, ... }:
let
  # SINGLE SOURCE OF TRUTH for the user-env leaf set (issue #338).
  shared = import ./shared-leaf-modules.nix { inherit lib pkgs; };
  hmThirdParty = [
    inputs.zen-browser.homeModules.twilight
    inputs.nixcord.homeModules.nixcord
    inputs.stylix.homeModules.default
    inputs.freebuff-flake.homeModules.default
  ];
in {
  # Stylix: base16 scheme + target empowerment, shared with the NixOS-module path
  # so both paths produce a fully-themed user env (previously only the
  # NixOS-module path empowered targets, leaving standalone unthemed).
  stylix = {
    enable = true;
    base16Scheme = ../../modules/desktop/themes/osaka-jade.yaml;
    polarity = "dark";
  } // shared.stylixTargets;

  imports = hmThirdParty ++ shared.leafModules ++ [
    # Per-host package lists (gaming/mining/monitoring tools) — these live only
    # here and are NOT in the NixOS-module path, so they deploy via `home-manager
    # switch` (layer 2), not `just deploy` (layer 1).
    ./standalone-zephyr.nix
    ./standalone-nexus.nix
    ./standalone-forge.nix
    ./standalone-sentry.nix
  ];

  programs.freebuff-desktop.enable = true;

  home.homeDirectory = "/home/j_kro";
  home.stateVersion = "26.05";
  home.username = "j_kro";
  home.pointerCursor = {
    enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Ice";
    size = 24;
  };

  programs.bash = {
    enable = true;
    initExtra = ''
      if [ -f ~/.bashrc ]; then
        source ~/.bashrc
      fi
    '';
  };

  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set -g fish_greeting
      fish_add_path /home/j_kro/bin
    '';
    loginShellInit = ''
      if test "$XDG_VTNR" = "1" -a -z "$WAYLAND_DISPLAY"
        exec uwsm start -F -- niri
      end
    '';
    shellAliases = {
      ll = "ls -la";
      la = "ls -A";
      l = "ls -CF";
      gs = "git status";
      ga = "git add";
      gc = "git commit";
      gp = "git push";
    };
  };

  programs.ssh = {
    enable = true;
    extraConfig = ''
      Host 10.1.1.*
        StrictHostKeyChecking no
        UserKnownHostsFile ~/.ssh/known_hosts
    '';
  };

  programs.gpg.enable = true;
  home.sessionVariables.BAT_THEME = "base16-stylix";
  systemd.user.sessionVariables.HF_TOKEN = "/run/secrets/huggingface-token";

  _module.args.hostName = lib.mkDefault hostName;
  _module.args.vfioPkgs = lib.mkDefault vfioPkgs;
  _module.args.inputs = lib.mkDefault inputs;
}

{ config, lib, pkgs, inputs, hostName, vfioPkgs, ... }:
let
  # SINGLE SOURCE OF TRUTH for the user-env leaf set (issue #338).
  shared = import ./shared-leaf-modules.nix { inherit lib pkgs; };
  hmThirdParty = [
    inputs.zen-browser.homeModules.twilight
    inputs.nixcord.homeModules.nixcord
    inputs.stylix.homeModules.default
    # NOTE: freebuff-flake is intentionally NOT imported here. freebuff-desktop
    # is an external CLI with no HM-managed dotfiles — it lives in Layer 3
    # (nix profile), per issue #338. Importing it into the HM layer causes a
    # `nix profile install` priority-5 collision with the Layer-3 entry
    # (both provide bin/freebuff-desktop). Keep it out of HM.
  ];
in {
  # Stylix: base16 scheme + target empowerment, shared with the NixOS-module path
  # so both paths produce a fully-themed user env (previously only the
  # NixOS-module path empowered targets, leaving standalone unthemed).
  nixpkgs.config.allowUnfree = true;

  stylix = {
    enable = true;
    base16Scheme = import ../../modules/desktop/themes/osaka-jade.nix;
    polarity = "dark";
    # Match the NixOS-path monospace font (modules/desktop/stylix.nix) so the
    # standalone HM build themes alacritty/kitty/starship with the same family
    # + size as the colmena path. Without this, stylix falls back to a default
    # monospace (DejaVu Sans Mono @ 12) and the terminal font diverges from the
    # system theme. `terminal = 10` (in stylixTargets) is the size token.
    fonts.monospace = {
      package = pkgs.nerd-fonts.jetbrains-mono;
      name = "JetBrainsMono Nerd Font";
    };
    # Pin all font sizes to 10. Without this, stylix defaults terminal to 12
    # (its upstream default), so alacritty/kitty render at the wrong size and
    # every `home-manager switch` reverts an imperative edit. GTK/Qt apps also
    # inherit `applications=12` default unless pinned here.
    fonts.sizes = {
      terminal = 10;
      applications = 10;
      desktop = 10;
      popups = 10;
    };
  } // shared.stylixTargets;

  imports = hmThirdParty
    ++ shared.leafModules
    ++ (shared.hostLeafModules.${hostName} or [])
    ++ [
    # Per-host package lists (gaming/mining/monitoring tools) — gated by hostName
    # so only the matching host's extras deploy via `home-manager switch`.
  ] ++ lib.optionals (hostName == "zephyr") [ ./standalone-zephyr.nix ]
    ++ lib.optionals (hostName == "nexus") [ ./standalone-nexus.nix ]
    ++ lib.optionals (hostName == "forge") [ ./standalone-forge.nix ]
    ++ lib.optionals (hostName == "sentry") [ ./standalone-sentry.nix ];

  # NOTE: freebuff-desktop is intentionally NOT enabled here. It is an external
  # CLI (no HM-managed dotfiles) that belongs in Layer 3 (nix profile), per
  # issue #338. Enabling it in HM triggers a `nix profile install` priority-5
  # collision with the Layer-3 freebuff-desktop entry (both provide
  # bin/freebuff-desktop). Remove this block — keep freebuff in Layer 3 only.

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
    enableDefaultConfig = false;
    enable = true;
    # Declare the default host block so the programs.ssh assertion
    # (extraConfig requires settings."*" to be declared) passes.
    settings."*" = {};
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

{
  config,
  lib,
  pkgs,
  inputs,
  hostName,
  vfioPkgs,
  ...
}:

let
  # Base16 scheme propagated into HM from the NixOS stylix module via
  # stylix.homeManagerIntegration.followSystem. The system scheme is
  # ./themes/osaka-jade.yaml (modules/desktop/stylix.nix). We reference the
  # same file here so a standalone `home-manager switch` (without the NixOS
  # layer) themes identically to colmena's `just switch`.
  stylixBase16 = ../../modules/desktop/themes/osaka-jade.yaml;

  hmThirdParty = [
    inputs.zen-browser.homeModules.twilight
    inputs.nixcord.homeModules.nixcord
    inputs.stylix.homeModules.default
    # niri HM module — required so `config.lib.niri` exists for niri-config.nix
    # (guarded internally by `config.lib ? niri`). Aligned with
    # modules/system/home-manager.nix which imports inputs.niri.homeModules.config.
    inputs.niri.homeModules.config
  ];

  hmLeaf = [
    ./fish.nix
    ./starship.nix
    ./btop.nix
    ./zen-browser.nix
    ./nixcord-config.nix
    ./mime-apps.nix
    ./mime-fix.nix
    ./caprine.nix
    ./opencode.nix
    ./firefox-pwa-apps.nix
    ./alacritty.nix
    ./hermes-skin.nix
    # Hermes Desktop .desktop entry (upstream package ships none).
    ./hermes-desktop.nix
    ./icon-theme.nix
    ./dolphin.nix
    ./desktop-utilities.nix
    ./copyq.nix
    ./git.nix
    ./tmux.nix
    ./lazygit.nix
    ./tui-apps.nix
    ./editorconfig.nix
    ./heal-stale-backups.nix
    # Noctalia -> stylix bridge (writes noctalia/colors.json + colorschemes).
    # Aligned with modules/system/home-manager.nix — was previously MISSING
    # from the standalone set, causing the standalone build to diverge from
    # the colmena-managed build on zephyr.
    ./noctalia-stylix.nix
    # Stylix bridges: purge stale noctalia.* orphan snapshots that shadow
    # stylix's live Osaka Jade base16 (alacritty theme, gtk css, btop theme,
    # qt colors, niri kdl, telegram theme, scroll). Also removes Kvantum state.
    ./stylix-bridges.nix
    # niri compositor config (zephyr/sentry). Guarded internally by
    # config.lib ? niri; only activates when the niri HM module is present.
    ./niri-config.nix
  ] ++ lib.optionals (hostName == "zephyr") [
    ./standalone-zephyr.nix
  ] ++ lib.optionals (hostName == "nexus") [
    ./standalone-nexus.nix
  ] ++ lib.optionals (hostName == "forge") [
    ./standalone-forge.nix
  ] ++ lib.optionals (hostName == "sentry") [
    ./standalone-sentry.nix
  ];
in {
  stylix = {
    enable = true;
    base16Scheme = stylixBase16;
    polarity = "dark";
  };
  imports = hmThirdParty ++ hmLeaf;

  # ── Backup extension ────────────────────────────────────────────
  # NOTE: in HM 0-unstable-2026-04-24 standalone, `home.backupFileExtension`
  # does NOT exist (it's only the NixOS/nix-darwin module option
  # `home-manager.backupFileExtension`). For the standalone flake we pass
  # the extension at switch time: `home-manager switch -b v3-fix`. The
  # `v3-fix` name matches the colmena path (modules/system/home-manager.nix)
  # so backups are consistent across both activation paths.

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

  # ── SSH (legacy matchBlocks API — HM 0-unstable-2026-04-24) ──────
  # `programs.ssh.settings` (RFC 42) does NOT exist in this HM version; the
  # repo's common.nix also uses matchBlocks/extraConfig, so we stay consistent.
  # Directives without a first-class field (strictHostKeyChecking,
  # addKeysToagent, pubkeyAuthentication, passwordAuthentication, batchMode,
  # connectTimeout) go in `extraOptions`, which renders verbatim.
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks = {
      "*" = {
        identityFile = "~/.ssh/id_ed25519_sk";
        identitiesOnly = true;
        serverAliveInterval = 60;
        forwardX11Trusted = true;
        extraOptions = {
          AddKeysToagent = "yes";
          ControlMaster = "auto";
          ControlPath = "~/.ssh/master-%r@%n:%p";
          ControlPersist = "10m";
          HashKnownHosts = "yes";
          UserKnownHostsFile = "~/.ssh/known_hosts";
        };
      };
      "sentry forge nexus" = {
        identityFile = "~/.ssh/id_ed25519_cluster";
        identitiesOnly = true;
        extraOptions = {
          StrictHostKeyChecking = "accept-new";
        };
      };
      "krash3-vm" = {
        hostname = "10.1.1.34";
        user = "j_kro";
        identityFile = "~/.ssh/id_ed25519_cluster";
        identitiesOnly = true;
        extraOptions = {
          StrictHostKeyChecking = "accept-new";
        };
      };
      "krash2" = {
        hostname = "10.1.1.79";
        user = "krash";
        identityFile = "~/.ssh/id_ed25519";
        identitiesOnly = true;
        extraOptions = {
          PubkeyAuthentication = "yes";
          PasswordAuthentication = "no";
        };
      };
      # NOTE: `krash3` and `10.1.1.150` are duplicate targets (same HostName,
      # identical settings) — preserved verbatim from the original plain file
      # for zero behavior change. Safe to delete one later.
      "krash3" = {
        hostname = "10.1.1.150";
        user = "j_kro";
        port = 22;
        identityFile = "~/.ssh/id_ed25519";
        extraOptions = {
          StrictHostKeyChecking = "no";
        };
      };
      "10.1.1.150" = {
        hostname = "10.1.1.150";
        user = "j_kro";
        port = 22;
        identityFile = "~/.ssh/id_ed25519";
        extraOptions = {
          StrictHostKeyChecking = "no";
        };
      };
      "krash3 10.1.1.150" = {
        hostname = "10.1.1.150";
        user = "j_kro";
        extraOptions = {
          BatchMode = "yes";
          StrictHostKeyChecking = "accept-new";
          ConnectTimeout = "8";
        };
      };
    };
  };

  programs.gpg.enable = true;
  home.sessionVariables.BAT_THEME = "base16-stylix";
  systemd.user.sessionVariables.HF_TOKEN = "/run/secrets/huggingface-token";

  # ── Stylix targets (aligned with modules/system/home-manager.nix) ─
  # autoEnable is false system-wide; empower explicitly so theming is
  # guaranteed regardless of auto-detect. Terminal-app targets live in the
  # HM stylix namespace (NOT config.stylix.targets.* at the NixOS level).
  stylix.targets = {
    zen-browser.profileNames = ["default"];
    starship.enable = true;
    alacritty.enable = true;
    kitty.enable = true;
    fish.enable = true;
    btop.enable = true;
    lazygit.enable = true;
    qt.enable = true;
    gtk.enable = true;
    bat.enable = true;
    fzf.enable = true;
    tmux.enable = true;
    opencode.enable = true;
    vesktop.enable = true;
  };

  # Non-Kvantum Qt path (niri + optional Plasma). adwaita-dark aligns with
  # polarity=dark and GTK adw-gtk3. mkForce resolves the priority clash.
  qt = {
    enable = true;
    platformTheme.name = lib.mkForce "gnome";
    style.name = lib.mkForce "adwaita-dark";
    kvantum.enable = lib.mkForce false;
  };
  home.sessionVariables.QT_STYLE_OVERRIDE = lib.mkForce "adwaita-dark";

  # Kitty terminal emulator (generates kitty.conf for stylix theming).
  programs.kitty.enable = true;

  xdg.configFile = {
    "mimeapps.list".force = true;
  };

  # starship.toml is HM-generated (programs.starship) but the live file is a
  # stale symlink to an old store path; checkLinkTargets refuses to repoint it
  # without force. programs.starship writes via home.file, so force there.
  home.file.".config/starship.toml".force = true;

  _module.args.hostName = lib.mkDefault hostName;
  _module.args.vfioPkgs = lib.mkDefault vfioPkgs;
  _module.args.inputs = lib.mkDefault inputs;
}

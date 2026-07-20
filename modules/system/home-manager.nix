{
  config,
  inputs,
  lib,
  pkgs,
  options,
  ...
}: let
  hostName = config.networking.hostName;
  # Check if home-manager option is DECLARED (not just defined) to avoid
  # "option does not exist" errors on hosts that don't import the HM module
  hasHM = builtins.hasAttr "home-manager" (builtins.tryEval options).value or {};
  # Check if the hermes-cli NixOS service option is DECLARED. Minimal hosts
  # (e.g. the usb rescue ISO) import a selective module set and run Hermes via
  # the hermes-agent package directly, so they have no services.hermes-cli.
  # Guard the hermes wrapper symlink on this to avoid "attribute missing" errors.
  hasHermesCli = (builtins.tryEval options).value ? services.hermes-cli;
in
  lib.mkIf hasHM {
  home-manager = {
    useGlobalPkgs = lib.mkDefault false;

    useUserPackages = true;

    # Use a unique backup extension that won't collide with previous backups.
    # Resolves "existing backup would be clobbered" failures on .hm-backup from
    # earlier failed HM activations (alacritty.toml, starship.toml, gtk.css).
    backupFileExtension = "v3-fix";

    extraSpecialArgs = {
      inherit inputs;
      inherit hostName;
      # Wrapped hermes binary (with PortAudio LD_LIBRARY_PATH) for the
      # user-local ~/.local/bin/hermes symlink (replaces stale manual link).
      # Null when the hermes-cli service isn't declared (e.g. usb rescue ISO).
      hermesWrappedBin = if hasHermesCli then config.services.hermes-cli.wrappedHermesBin else null;
      # Expose the noctalia wrapper (NixOS `programs.noctalia.package`,
      # mkForce'd to the pass-through wrapper in
      # modules/desktop/wayland-compositor-common.nix) to home-manager
      # modules. Home-manager's `config` does NOT see NixOS options, so
      # niri-config.nix spawns it via this injected arg rather than
      # `config.programs.noctalia.package`.
      noctaliaPackage = config.programs.noctalia.package;
    };

    users.j_kro = { hermesWrappedBin, ... }: {
      # Home Manager uses separate nixpkgs config for user packages
      # Allow insecure packages
      nixpkgs.config.permittedInsecurePackages = [
        "pnpm-10.29.2"
        "vesktop-1.6.5"
        # vesktop pulls electron-40.10.5 (EOL, marked insecure); HM has its own
        # nixpkgs config so the system-level permit in nix-config.nix doesn't
        # reach it. Added 2026-07-16.
        "electron-40.10.5"
      ];

      imports =
        lib.optional (hostName == "zephyr" || hostName == "sentry")
          inputs.niri.homeModules.config
        ++ [
          inputs.stylix.homeModules.default
          inputs.zen-browser.homeModules.twilight
        inputs.nixcord.homeModules.nixcord
        ../../modules/home-manager/fish.nix
        ../../modules/home-manager/starship.nix
        # ../../modules/home-manager/wayland-tools.nix
        ../../modules/home-manager/zen-browser.nix
        ../../modules/home-manager/nixcord-config.nix
        ../../modules/home-manager/caprine.nix
        # ../../modules/home-manager/obsidian.nix  # Temporarily disabled - stylix integration issue
        ../../modules/home-manager/opencode.nix
        ../../modules/home-manager/firefox-pwa-apps.nix
        ../../modules/home-manager/freebuff-desktop.nix
        ../../modules/home-manager/alacritty.nix
        ../../modules/home-manager/hermes-skin.nix
        ../../modules/home-manager/icon-theme.nix
        ../../modules/home-manager/dolphin.nix
        ../../modules/home-manager/desktop-utilities.nix
        ../../modules/home-manager/copyq.nix
        ../../modules/home-manager/git.nix
        ../../modules/home-manager/tmux.nix
        ../../modules/home-manager/lazygit.nix
        ../../modules/home-manager/mime-apps.nix
        ../../modules/home-manager/tui-apps.nix
        ../../modules/home-manager/editorconfig.nix
        ../../modules/home-manager/btop.nix
        ../../modules/home-manager/noctalia-stylix.nix
        # Wires the removeStaleNoctaliaThemes activation so frozen v4
        # noctalia.* orphans (alacritty theme, gtk css, btop theme, qt
        # colors, niri kdl, telegram theme, scroll) are deleted on switch
        # and can no longer bypass stylix. Was previously dead code
        # (never imported) — see stylix audit 2026-07-16.
        ../../modules/home-manager/stylix-bridges.nix
      ]
      # niri-config only on hosts with the niri HM module
      ++ lib.optional (hostName == "zephyr" || hostName == "sentry")
        ../../modules/home-manager/niri-config.nix;

      nixcord-config.enable = lib.mkForce (hostName == "zephyr");
      caprine.enable = lib.mkForce (hostName == "zephyr");

      # Stylix - inherit from system config for home-manager
      stylix = {
        inherit (config.stylix) base16Scheme;
        inherit (config.stylix) image;
        targets.zen-browser.profileNames = ["default"];

        # ── Explicit target empowerment (version-bump-proof) ───────
        # autoEnable is false system-wide, so with autoImport/followSystem
        # the HM targets are still auto-enabled by stylix's HM module ONLY
        # when the program is installed. That dependency chain is fragile
        # (a stylix rev bump or a mkForce can silently drop theming).
        # Explicitly empower every target we actually run so the theme is
        # guaranteed regardless of auto-detect. Terminal-app targets live
        # in the HM stylix namespace (NOT config.stylix.targets.* at the
        # NixOS level, which only carries system targets like lightdm).
        targets.starship.enable = true;
        targets.alacritty.enable = true;
        targets.kitty.enable = true;
        targets.fish.enable = true;
        targets.btop.enable = true;
        targets.lazygit.enable = true;
        targets.qt.enable = true;
        # GTK theming requires dconf/D-Bus which isn't available on nexus
        targets.gtk.enable = hostName != "nexus";
      };

      # CopyQ clipboard manager (replaces cliphist)
      programs.copyq = {
        enable = lib.mkDefault true;
      };

      home.sessionVariables.BAT_THEME = "base16";

      home.pointerCursor.enable = true;

      home.stateVersion = "26.05";
      home.enableNixpkgsReleaseCheck = false;

      xdg.configFile = {
        "mimeapps.list".force = true;
      };

      home.sessionVariables = {
        HF_TOKEN = "/run/secrets/huggingface-token";
      };

      # Ensure the user's ~/.local/bin/hermes points at the NixOS-wrapped
      # hermes binary (which carries the PortAudio LD_LIBRARY_PATH). A stale
      # manual symlink to a raw GC-able store path previously shadowed the
      # system wrapper and broke voice mode. force=true overrides it.
      # Skipped on hosts without the hermes-cli service (e.g. usb rescue ISO,
      # which ships hermes via the hermes-agent package directly).
      home.file.".local/bin/hermes" = lib.mkIf (hermesWrappedBin != null) {
        source = hermesWrappedBin;
        force = true;
      };

      # Remove stale HM backup files before activation to prevent clobber errors
      home.activation.removeStaleBackups = ''
        # Old extension (gone on next activation) and new extension (until clean state)
        for ext in hm-backup v3-fix; do
          rm -f "$HOME/.config/alacritty/alacritty.toml.$ext"
          rm -f "$HOME/.config/starship.toml.$ext"
          rm -f "$HOME/.config/fish/config.fish.$ext"
          rm -f "$HOME/.config/gtk-3.0/gtk.css.$ext"
          rm -f "$HOME/.config/gtk-4.0/gtk.css.$ext"
        done
      '';

      # Auto-migrate Alacritty config after activation (removes deprecation warnings)
      home.activation.migrateAlacrittyConfig = ''
        if [ -f "$HOME/.config/alacritty/alacritty.toml" ]; then
          ${pkgs.alacritty}/bin/alacritty migrate -c "$HOME/.config/alacritty/alacritty.toml" 2>/dev/null || true
        fi
      '';

      # ── Self-healing HM-ownership drift guard ──────────────────
      # Root cause of recurring stylix/dotfile drift: HM-owned dotfiles get
      # frozen as plain 0444 files (manual edit, failed activation) and HM
      # can no longer overwrite/relink them on switch — so they shadow the
      # generated stylix version forever. This guard detects any known
      # HM-managed dotfile that is a REGULAR FILE (not a symlink into the
      # store generation), makes it writable, and warns. With write perms,
      # HM's own activation reclaims it (moves to .hm-backup, relinks from
      # store) on the SAME switch. Never deletes — safe by design.
      # List = files HM generates via programs.* / xdg.configFile / stylix.
      home.activation.healHMDrift = ''
        for f in \
          "$HOME/.config/starship.toml" \
          "$HOME/.config/alacritty/alacritty.toml" \
          "$HOME/.config/btop/btop.conf" \
          "$HOME/.config/fish/config.fish" \
          "$HOME/.config/gtk-3.0/gtk.css" \
          "$HOME/.config/gtk-4.0/gtk.css" \
          "$HOME/.config/lazygit/config.yml" \
          "$HOME/.config/kitty/kitty.conf" ; do
          if [ -e "$f" ] && [ ! -L "$f" ]; then
            echo "healHMDrift: $f drifted from HM (plain file) — un-freezing so HM can reclaim it"
            chmod u+w "$f" 2>/dev/null || true
          fi
        done
      '';
    };
  };
}

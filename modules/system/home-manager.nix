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
  # SINGLE SOURCE OF TRUTH for the user-env leaf set (issue #338).
  shared = import ../home-manager/shared-leaf-modules.nix { inherit lib pkgs; };
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
         # Expose the noctalia wrapper (NixOS `programs.noctalia.package`,
         # mkForce'd to the pass-through wrapper in
         # modules/desktop/wayland-compositor-common.nix) to home-manager
         # modules. HM's `config` does NOT see NixOS options, so niri-config.nix
         # spawns it via this injected arg rather than `config.programs.noctalia`.
         # HM-module-path only — standalone HM excludes niri-config.
         noctaliaPackage =
           if config ? programs.noctalia
           then config.programs.noctalia.package
           else "";
       };

       users.j_kro = { ... }: {
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
            inputs.zen-browser.homeModules.twilight
            inputs.nixcord.homeModules.nixcord
          ]
          ++ shared.leafModules
          # NixOS-coupled extras — NOT in shared leaf set (would break standalone):
          # niri-config reads HM stylix + spawns noctalia via injected arg.
          ++ lib.optional (hostName == "zephyr" || hostName == "sentry")
          ../../modules/home-manager/niri-config.nix;

        # Stylix target empowerment (shared with standalone path).
        # Set ONLY stylix.targets here: the NixOS stylix module owns
        # stylix.base16 (read-only, propagated to HM via followSystem), so
        # assigning the whole `stylix` attr would redefine base16 and error.
        stylix.targets = shared.stylixTargets.targets;

        # ── Additional explicit targets (mirror standalone) ──
        nixcord-config.enable = lib.mkForce (hostName == "zephyr");
        caprine.enable = lib.mkForce (hostName == "zephyr");

        # Non-Kvantum Qt path for all hosts (niri + optional Plasma).
        # adwaita-dark aligns with polarity=dark and GTK adw-gtk3.
        qt = {
          enable = true;
          platformTheme.name = lib.mkForce "adwaita";
          style.name = lib.mkForce "adwaita-dark";
          kvantum.enable = lib.mkForce false;
        };
        home.sessionVariables.QT_STYLE_OVERRIDE = lib.mkForce "adwaita-dark";
        home.pointerCursor.enable = true;

        # CopyQ clipboard manager (replaces cliphist)
        programs.copyq = {
          enable = lib.mkDefault true;
        };
        # Kitty terminal emulator (generates kitty.conf for stylix theming)
        programs.kitty.enable = true;

        home.sessionVariables.BAT_THEME = "base16-stylix";

        home.stateVersion = "26.05";
        home.enableNixpkgsReleaseCheck = false;

        xdg.configFile = {
          "mimeapps.list".force = true;
        };

        home.sessionVariables = {
          HF_TOKEN = "/run/secrets/huggingface-token";
        };

        xdg.configFile = {
          "mimeapps.list".force = true;
        };
        home.activation.migrateAlacrittyConfig = ''
          if [ -f "$HOME/.config/alacritty/alacritty.toml" ]; then
            ${pkgs.alacritty}/bin/alacritty migrate -c "$HOME/.config/alacritty/alacritty.toml" 2>/dev/null || true
          fi
        '';
      };
    };
  }

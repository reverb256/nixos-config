# LEGACY COMPATIBILITY SHIM: active standalone Home Manager configuration now
# lives in /home/j_kro/Projects/home-manager-config. Do not add user features
# here; this file remains only for the legacy NixOS-module path and layer
# contract checks during the repository migration.
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
  # SINGLE SOURCE OF TRUTH for the user-env leaf set (issue #338).
  # Imported from the home-manager-config flake input (reverb256/home-manager-config),
  # NOT from a local copy. This is the only HM leaf module loaded directly here;
  # everything else flows through shared.leafModules / shared.hostLeafModules.
  shared = (import "${inputs.home-manager-config}/modules/shared-leaf-modules.nix" { inherit lib pkgs; });
in
  lib.mkIf hasHM {
    home-manager = {
      # Share the NixOS package set so integrated HM packages preserve the
      # same derivation identity as system packages and can use the same
      # Hydra/CUDA/Cachix substitutes. HM-local nixpkgs.* options are
      # intentionally removed below; the system package policy owns them.
      useGlobalPkgs = true;

      useUserPackages = true;

      # Canonical collision handler (home-manager manual): HM moves shadowing
      # plain files to `<file>.backup` itself and clobbers stale backups, so
      # `just switch` never aborts on "would be clobbered". No activation hack.
      backupFileExtension = "backup";
      overwriteBackup = true;

      extraSpecialArgs = {
        inherit inputs;
        inherit hostName;
        # Wrapped hermes binary (with PortAudio LD_LIBRARY_PATH) for the
        # user-local ~/.local/bin/hermes symlink. Null when hermes-cli service
        # isn't declared (e.g. usb rescue ISO). HM-module-path only; standalone
        # HM resolves hermes from the nix profile layer (#334), so this arg is
        # never required there.
        hermesWrappedBin =
          if hasHermesCli
          then config.services.hermes-cli.wrappedHermesBin
          else null;
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

      users.j_kro = {hermesWrappedBin, ...}: {
        # HM uses the NixOS package set (`useGlobalPkgs = true`). Unfree and
        # insecure permissions are declared once by the system package policy
        # in modules/system/nix-config.nix, so this user module must not define
        # a second nixpkgs scope.

        imports =
          lib.optional (hostName == "zephyr" || hostName == "sentry")
          inputs.niri.homeModules.config
          ++ [
            inputs.zen-browser.homeModules.twilight
            inputs.nixcord.homeModules.nixcord
          ]
          ++ shared.leafModules
          ++ (shared.hostLeafModules.${hostName} or [])
          # NixOS-coupled extras — NOT in shared leaf set (would break standalone):
          # niri-config reads HM stylix + spawns noctalia via injected arg.
          ++ lib.optional (hostName == "zephyr" || hostName == "sentry")
          "${inputs.home-manager-config}/modules/niri-config.nix";

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

        # VR/Steam user configuration moved to the active standalone
        # Home Manager leaf in home-manager-config. Keep this NixOS bridge
        # limited to the shared HM integration; it is retained because the
        # layer-contract test and legacy NixOS-module path still reference it.
        xdg.configFile = {
          "mimeapps.list".force = true;

          # VR: OpenVR -> WiVRn bridge (LVRA NixOS page + NixOS wiki/VR).
          # VRChat (OpenVR) can't see the WiVRn OpenXR runtime unless its
          # openvrpaths.vrpath points xrizer at the runtime. SteamVR writes its
          # own path back if this file is mutable, so HM owns it (read-only
          # symlink). Point ONLY at xrizer -- not SteamVR -- so OpenVR games use
          # WiVRn without launching SteamVR. WiVRn auto-switches the active
          # OpenXR runtime on headset connect; this file is the OpenVR side.
          "openvr/openvrpaths.vrpath".text = lib.mkIf (hostName == "zephyr") (let
            steam = "${config.xdg.dataHome}/Steam";
          in builtins.toJSON {
            version = 1;
            jsonid = "vrpathreg";
            external_drivers = null;
            config = [ "${steam}/config" ];
            log = [ "${steam}/logs" ];
            runtime = [ "${pkgs.xrizer}/lib/xrizer" ];
          });
        };

        home.sessionVariables = {
          HF_TOKEN = "/run/secrets/huggingface-token";
        };

        # Ensure the user's ~/.local/bin/hermes points at the NixOS-wrapped
        # hermes binary (carries PortAudio LD_LIBRARY_PATH). Standalone HM path
        # omits this — hermes comes from the nix profile layer there (#334).
        home.file.".local/bin/hermes" = lib.mkIf (hermesWrappedBin != null) {
          source = hermesWrappedBin;
          force = true;
        };

        # Auto-migrate Alacritty config after activation (removes deprecation warnings)
        home.activation.migrateAlacrittyConfig = ''
          if [ -f "$HOME/.config/alacritty/alacritty.toml" ]; then
            ${pkgs.alacritty}/bin/alacritty migrate -c "$HOME/.config/alacritty/alacritty.toml" 2>/dev/null || true
          fi
        '';
      };
    };
  }
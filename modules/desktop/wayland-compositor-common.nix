{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  inherit (lib) mkIf;
  niriEnabled = config.programs.niri.enable or false;
  noctaliaAvailable =
    inputs ? noctalia
    && inputs.noctalia ? packages
    && inputs.noctalia.packages ? ${pkgs.stdenv.hostPlatform.system};
  # ── noctalia brightness wrapper ─────────────────────────────────────
  # noctalia v5 dropped the v4 brightness plugin (no built-in IPC for
  # `brightness-up/down/get/set`). The wrapper shim at
  # scripts/brightness-router.sh restores the v4 IPC surface and routes
  # each verb to one of two backends per-output (DDC/CI or niri's
  # NV_PLANE_DEGAMMA_MULTIPLIER patch). All other v5 IPC subcommands
  # (panel-toggle, theme-mode-toggle, settings-toggle, …) pass through.
  noctaliaBin = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
  noctaliaWrapped = pkgs.writeShellScriptBin "noctalia" ''
    if [[ "$1" == "msg" ]]; then
      case "$2" in
        brightness-up|brightness-down|brightness-get|brightness-set)
          # Path: from modules/desktop/ go up two levels to repo root, then into scripts/
          exec ${./../../scripts/brightness-router.sh} "$2" "''${@:3}"
          ;;
      esac
    fi
    exec ${noctaliaBin}/bin/noctalia "$@"
  '';
in {
  config = mkIf noctaliaAvailable {
    # ── Install noctalia v5 binary (wrapped) ────────────────────────────
    # We use `environment.systemPackages` directly (with `lib.mkOptionDefault`
    # per AGENTS.md cluster convention for extensible lists) instead of setting
    # `programs.noctalia.package`. The upstream noctalia v5 nixosModule declares
    # `programs.noctalia.package = mkOption { default = null; ... }` and
    # assigning an explicit value conflicts with that declaration at flake
    # check time ("defined multiple times and expected to be unique").
    # environment.systemPackages is a NixOS-managed list with built-in list
    # merging across modules — safe in a shared module. We swap the upstream
    # binary for a wrapper at this layer so the brightness IPC contract from
    # v4 is preserved.
    # Plain `[ noctaliaWrapped ]` (NOT `lib.mkOptionDefault`):
    # mkOptionDefault drops priority to 1500; other modules set
    # environment.systemPackages at standard priority 100 with non-empty
    # lists. Nix's list-merge across priorities discards the 1500 entry
    # entirely, so the wrapper would never reach PATH.
    # Lists auto-concatenate at standard priority, so a plain
    # `[ noctaliaWrapped ]` here merges cleanly with every other module.
    environment.systemPackages = [
      noctaliaWrapped
    ];

    # ── Force-disable upstream noctalia module's binary install ────────
    # The upstream nixosModule adds the upstream `noctalia` binary to
    # `environment.systemPackages` whenever `programs.noctalia.enable = true`.
    # Our `lib.mkOptionDefault [ noctaliaWrapped ]` adds our wrapper to the
    # same list. NixOS symlink-union merges the two `bin/noctalia` entries
    # but PATH ordering across the merge is not deterministic — upstream
    # could win, silently breaking the brightness IPC dispatcher. The
    # targeted `mkForce false` here ensures ONLY our wrapper is on PATH.
    # The noctalia nixosModule's other side-effects (DE integration, asset
    # paths, etc.) are all declarative and unused here, so disabling is safe.
    programs.noctalia.enable = lib.mkForce false;

    # Was: programs.noctalia.enable = mkIf niriEnabled true;
    # Replaced because of the PATH-ordering collision with our wrapper.

    # ── SSH agent conflict resolution ──────────────────────────────────
    # REQUIRED — NixOS asserts that `programs.ssh.startAgent = true` (set
    # globally by modules/system/distributed-builds.nix for cluster-wide
    # distributed builds) cannot coexist with `services.gnome.gcr-ssh-agent.enable`.
    # The cluster uses the system ssh-agent for handoff to build users;
    # disabling the GNOME ssh-agent daemon is the project-wide convention.
    # We do NOT disable `services.gnome.gnome-keyring` here — NixOS upstream
    # `programs/wayland/niri.nix` auto-sets it to `true` whenever
    # `programs.niri.enable = true` and toggling it off triggers a NixOS
    # assertion. Per-user Secret Service activation still works on demand.
    services.gnome.gcr-ssh-agent.enable = lib.mkDefault false;
  };
}

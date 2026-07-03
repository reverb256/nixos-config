{
  config,
  lib,
  pkgs,
  inputs,
  options,
  ...
}:
let
  inherit (lib) mkIf mkDefault;
  noctaliaEnabled = options ? programs.noctalia.enable;
in
  mkIf (config.programs.niri.enable or false) {

    # ── SSH agent conflict resolution ──────────────────────────────────
    # REQUIRED — NixOS asserts that `programs.ssh.startAgent = true` (set
    # globally by modules/system/distributed-builds.nix for cluster-wide
    # distributed builds) cannot coexist with `services.gnome.gcr-ssh-agent.enable`.
    services.gnome.gcr-ssh-agent.enable = mkDefault false;

    # ── Install noctalia v5 binary (wrapped) if noctalia module is present ─
    environment.systemPackages = mkIf noctaliaEnabled [
      (pkgs.writeShellScriptBin "noctalia" ''
        if [[ "$1" == "msg" ]]; then
          case "$2" in
            brightness-up|brightness-down|brightness-get|brightness-set)
              exec ${./../../scripts/brightness-router.sh} "$2" "''${@:3}"
              ;;
          esac
        fi
        exec ${inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/noctalia "$@"
      '')
    ];
  }

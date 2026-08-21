# ─────────────────────────────────────────────────────────────────────────────
# systemd-mask — fleet-wide masking of inert systemd components.
#
# These units are socket/D-Bus activated and never used on this fleet (no
# portable services, no image imports, podman/k3s own the container layer).
# Verified live 2026-08-21 on all 4 hosts: no processes, MemoryCurrent unset,
# importd socket self-deactivates. Masking is a security-posture hardening
# (remove the listening socket + D-Bus API surface), NOT a resource saving —
# socket activation already costs ~nothing until used.
#
# Research basis: systemd upstream treats these as low-level components
# (systemd/systemd#15175); hardening practice favors minimal service count.
# On NixOS, userdb/homed units do NOT ship, so only portabled + importd are
# masked here.
#
# Mechanism: `systemd.units.<name>.enable = false` — nixpkgs documents this
# as "If set to false, this unit will be a symlink to /dev/null", i.e. the
# declarative equivalent of `systemctl mask`.
# ─────────────────────────────────────────────────────────────────────────────
{
  lib,
  ...
}: {
  config = {
    systemd.units = {
      # Mask the portable-services daemon. Accepts untrusted OS-tree images;
      # nothing on the fleet uses portablectl, so remove the surface entirely.
      "systemd-portabled.service".enable = false;
      # Mask the image import/export daemon + its socket. Verified inert on
      # all hosts — nothing connects to the io.systemd.Import socket.
      # mkForce: nixpkgs' systemd module sets importd.service.enable=true
      # (wired via withImportd); we deliberately override that upstream default.
      "systemd-importd.service".enable = lib.mkForce false;
      "systemd-importd.socket".enable = false;
    };
  };
}

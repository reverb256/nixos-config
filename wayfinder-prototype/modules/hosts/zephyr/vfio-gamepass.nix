# Zephyr host-private module (host-wiring Q3 → B)
#
# Exactly-one-host feature: the VFIO Game Pass Windows VM (RTX 3060 Ti
# passthrough). Lives under modules/hosts/<host>/ because only zephyr uses it —
# it is NOT a shared feature (nexus/forge/sentry would never import it).
#
# Real repo: modules/hardware/vfio-gamepass.nix. This is a minimal stand-in so
# the reference flake evaluates; the real conversion wraps its body verbatim in
# flake.modules.nixos.vfio-gamepass.
{ inputs, ... }: {
  flake.modules.nixos.vfio-gamepass = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.vfio-gamepass = {
      enable = lib.mkEnableOption "VFIO Game Pass Windows VM (RTX 3060 Ti)";
      vfioPkgs = lib.mkOption {
        type = lib.types.attrs;
        description = "VFIO package set (kvmfr, looking-glass, qemu) — per Q1=A vfioPkgs lives HERE, not in specialArgs";
      };
    };

    config = lib.mkIf config.vfio-gamepass.enable {
      # Real content: kvmfr module, qemu/libvirt, Looking Glass, VM systemd
      # service... (from modules/hardware/vfio-gamepass.nix verbatim).
    };
  };
}

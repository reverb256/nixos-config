# Zephyr host-private module (host-wiring Q3 → B)
#
# Exactly-one-host feature: PeakMiner GPU mining stack (zephyr local miners +
# auth-translator proxies). Lives under modules/hosts/<host>/ because only
# zephyr uses it.
#
# Real repo: hosts/zephyr/peakminer.nix (already a host-local file). This is a
# minimal stand-in so the reference flake evaluates; the real conversion wraps
# its body verbatim in flake.modules.nixos.peakminer.
{ inputs, ... }: {
  flake.modules.nixos.peakminer = {
    config,
    lib,
    pkgs,
    ...
  }: {
    options.peakminer = {
      enable = lib.mkEnableOption "PeakMiner GPU mining";
    };

    config = lib.mkIf config.peakminer.enable {
      # Real content: systemd services for local miners + auth-translator
      # proxies (from hosts/zephyr/peakminer.nix verbatim).
    };
  };
}

# Desktop-only NixOS module bundling AAGL + Stylix + Niri overlay.
# Loaded ONLY via flake.nix `hosts.zephyr.extraModules` (zephyr is the
# gaming / Wayland workstation host). Keeping these out of
# common-modules-list.nix prevents nexus/forge/sentry (headless) from
# paying the eval tax on color palettes, cursor themes, the GNOME app
# lens, and the Niri package overlay.
#
# Ref: docs/audit-2026-07-27.md F-13 (transitively-bloated common-modules).
#
# Each sub-entry under `imports` is itself a NixOS module — NixOS will
# flake module + an inline anonymous module declaring the Niri overlay.
# The inline { ... } attrset is necessary because nixpkgs.overlays is a
# top-level Nixpkgs option that only takes effect via the modules
# system, not via direct config assignment in a flake helper.
#
# Behaviour notes:
#   - home-manager stays in common-modules-list.nix because the cluster-
#     mesh / j_kro home environment is evaluated on every host for ssh /
#     wrapper consistency, not just desktop hosts.
#   - llm-agents.overlays.shared-nixpkgs, self.overlays.default, and
#     inputs.lsfg-vk-nix.overlays.default stay in common-modules-list.nix
#     because peakminer and ai-gateway pipelines run on nexus / forge /
#     sentry too.
#
# To add a 5th host: just add it to `hosts` in flake.nix with
# `extraModules = []` for headless, or
# `extraModules = [ ./modules/desktop/desktop-modules.nix ]` for desktop.
{
  inputs,
  ...
}: {
  imports = [
    inputs.aagl.nixosModules.default
    ./aagl.nix


    {
      # Niri package overlay — desktop-only. The remaining cluster-wide
      # overlays (llm-agents.shared-nixpkgs, self.overlays.default,
      # inputs.lsfg-vk-nix.overlays.default) stay in common-modules-list.nix
      # because their consumers run on headless servers too.
      nixpkgs.overlays = [
        inputs.niri.overlays.niri
      ];
    }
  ];
}

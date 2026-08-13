# Host registry aggregator — flake-parts module.
#
# flake.nix imports this ONCE (`./modules/hosts/default.nix`). Each host is a
# directory under ./ with a default.nix that registers
# `flake.nixosConfigurations.<host>` AND `flake.modules.nixos.<host>Config`
# (the two-layer convention).
#
# Adding a host = one line here + modules/hosts/<host>/default.nix.
#
# Migration complete (2026-08-13): ALL four hosts are dendritic.
# Rollout order: zephyr (#398) → forge (#411/#413) → nexus → sentry.
# No host remains on the classic shim (common-modules-list.nix + mkNixosSystem);
# the shim in flake.nix now has an empty classicHosts set and is a
# legacy carve-out pending dissolution.
{imports = [./zephyr ./forge ./nexus ./sentry];}

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
# The classic shim (common-modules-list.nix + mkNixosSystem) is fully
# dissolved: no classicHosts, classicNixosConfigurations, or oracle remain.
# Hosts compose the shared lib/dendritic-host.nix evaluator — the same
# module-list + specialArgs contract colmena.nix uses.
{imports = [./zephyr ./forge ./nexus ./sentry];}

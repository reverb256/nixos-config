# Host registry aggregator — flake-parts module.
#
# flake.nix imports this ONCE (`./modules/hosts/default.nix`). Each host is a
# directory under ./ with a default.nix that registers
# `flake.nixosConfigurations.<host>` AND `flake.modules.nixos.<host>Config`
# (the two-layer convention).
#
# Adding a host = one line here + modules/hosts/<host>/default.nix.
#
# Incremental rollout (map: zephyr → forge → sentry → nexus (nexus skipped while down): this registry
# currently registers zephyr + forge. nexus/forge/sentry join here as their
# cutover lands, while they stay on the classic shim (common-modules-list.nix
# + mkNixosSystem) until then.
{ imports = [ ./zephyr ./forge ]; }

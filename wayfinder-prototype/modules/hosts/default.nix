# Host registry aggregator (host-wiring Q7 → B)
#
# flake.nix imports this ONCE (`./modules/hosts`). Each host is a directory
# under ./ with a default.nix that registers `flake.nixosConfigurations.<host>`
# AND `flake.nixosModules.<host>Config` (the two-layer convention, Q1 → B).
#
# Adding a host = one line here + modules/hosts/<host>/default.nix.
#
# Incremental rollout (map: zephyr first): this reference only registers
# zephyr. nexus/forge/sentry join here as their cutover lands (execute
# tickets), while they stay on the classic shim (common-modules-list.nix +
# mkNixosSystem) — mechanics research: shim module keeps other 3 hosts
# classic meanwhile.
{ imports = [ ./zephyr ]; }

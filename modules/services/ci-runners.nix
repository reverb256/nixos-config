# Minimal reproduction: does declaring services.ci-runners.instances + minimal
# config trigger the colmena recursion on nexus?
{
  config,
  lib,
  ...
}: {
  options.services.ci-runners = {
    instances = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = {};
    };
  };
  config = {
    # no-op config to prove the option declaration alone is safe
  };
}

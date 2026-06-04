{
  config,
  lib,
  pkgs,
  ...
}: {
  options.cluster = {
    config = lib.mkOption {
      type = lib.types.submodule {
        freeformType = lib.types.attrs;
      };
      default = {
        name = "j_kro-homelab";
        domain = "cluster.local";
        podCidr = "10.42.0.0/16";
        serviceCidr = "10.96.0.0/12";
        kubeVip = "10.1.1.100";
        hosts = {};
      };
    };
  };
}

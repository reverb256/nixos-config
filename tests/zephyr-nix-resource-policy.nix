{pkgs ? import <nixpkgs> {}}: let
  inherit (pkgs) lib;
  source = builtins.readFile ../hosts/zephyr/configuration.nix;
  has = needle: lib.strings.hasInfix needle source;

  checks = {
    enablesBuildCgroups = has "use-cgroups = true;";
    enablesCgroupFeature = has "extra-experimental-features = [ \"cgroups\" ];";
    usesIdleCpuScheduling = has "daemonCPUSchedPolicy = \"idle\";";
    usesIdleIoScheduling = has "daemonIOSchedClass = \"idle\";";
    delegatesNixDaemon = has "Delegate = true;";
    delegatesSupervisorSubgroup = has "DelegateSubgroup = \"supervisor\";";
  };

  failures = lib.filterAttrs (_: passed: !passed) checks;
in {
  inherit checks failures;
  passed = failures == {};
}

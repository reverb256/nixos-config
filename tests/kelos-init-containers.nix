# Test that Kelos TaskSpawner pods have proper initContainer entrypoint overrides
# This validates that alpine/git init containers override the default "git" ENTRYPOINT

{ lib, ... }:
let
  # Helper to check if initContainers override exists and is correct
  checkInitContainers = taskSpawner: {
    initContainers = taskSpawner.spec.taskTemplate.podOverrides.initContainers or [];
    gitCloneOk = lib.any (c: c.name == "git-clone" && c.entrypoint == []) initContainers;
    branchSetupOk = lib.any (c: c.name == "branch-setup" && c.entrypoint == []) initContainers;
  };
in
{
  # This test will fail until initContainers entrypoint override is added
  test-init-containers-have-entrypoint-override = {
    expression = checkInitContainers (builtins.head (import ../kubernetes/modules/kelos.nix).taskSpawners."github-issues-maplespike");
    expected = {
      gitCloneOk = true;
      branchSetupOk = true;
    };
  };
}
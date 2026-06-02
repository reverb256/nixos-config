# Hermes Workspace — ARCHIVED (2026-05-16)
# Project deleted from /data/projects/own/
# This module is kept as placeholder for potential future restoration.
{
  config,
  lib,
  ...
}: {
  options.services.hermes-workspace = {
    enable = lib.mkEnableOption "Hermes Workspace Web UI (archived)";
  };

  config = lib.mkIf config.services.hermes-workspace.enable {
    warnings = ["services.hermes-workspace is archived - the project was deleted on 2026-05-16"];
  };
}

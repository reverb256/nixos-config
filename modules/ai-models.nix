{ lib, config, ... }:
let
  models = builtins.fromTOML (builtins.readFile /etc/nixos/ai-models.toml);
in {
  options.ai-models = lib.mkOption {
    type = lib.types.attrs;
    default = {};
    description = "AI Models Registry — single source of truth for all model declarations";
  };
  config.ai-models = models;
}

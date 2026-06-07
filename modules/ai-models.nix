{
  lib,
  config,
  ...
}: let
  # Primary registry (single source of truth)
  nixRegistry = import ../kubernetes/curated-models.nix;

  # TOML registry (secondary, for tools that expect TOML)
  tomlModels = builtins.fromTOML (builtins.readFile ../ai-models.toml);

  cfg = config.ai-models;
in {
  options.ai-models = {
    enable = lib.mkEnableOption "AI Models Registry";
    registry = lib.mkOption {
      type = lib.types.attrs;
      default = nixRegistry;
      description = ''
        Unified AI model registry.
        Primary source: kubernetes/curated-models.nix (Nix format, comprehensive)
        Secondary source: ai-models.toml (TOML format, validation tooling)
      '';
    };
    models = lib.mkOption {
      type = lib.types.attrs;
      default = nixRegistry.models;
      description = "All AI model definitions";
    };
    providers = lib.mkOption {
      type = lib.types.attrs;
      default = nixRegistry.providers;
      description = "Provider configurations";
    };
    defaults = lib.mkOption {
      type = lib.types.attrs;
      default = nixRegistry.defaults;
      description = "Default model assignments for each role";
    };
  };

  config = lib.mkIf cfg.enable {
    ai-models = {
      registry = nixRegistry;
      inherit (nixRegistry) models;
      inherit (nixRegistry) providers;
      inherit (nixRegistry) defaults;
    };
  };
}

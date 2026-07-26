{ config, lib, inputs, ... }: let
  inherit (lib) mkOption types mkIf;
in {
  options.services.sops-secrets-registry = {
    enable = mkOption { type = types.bool; default = false; };
    aiServices = mkOption { type = types.bool; default = false; };
    kubernetes = mkOption { type = types.bool; default = false; };
    cloud = mkOption { type = types.bool; default = false; };
    monitoring = mkOption { type = types.bool; default = false; };
    mining = mkOption { type = types.bool; default = false; };
    storage = mkOption { type = types.bool; default = false; };
    automation = mkOption { type = types.bool; default = false; };
    selfHosting = mkOption { type = types.bool; default = false; };
    ci = mkOption { type = types.bool; default = false; };
    cache = mkOption { type = types.bool; default = false; };
  };
  config = mkIf config.services.sops-secrets-registry.enable {
    sops = {
      defaultSopsFile = "${inputs.self}/secrets/ai/nvidia-api-key.yaml";
      defaultSopsFormat = "binary";
      age.keyFile = "/etc/nixos/.age/key.txt";
      secrets = {};
    };
  };
}

{
  config,
  lib,
  inputs,
  ...
}: let
  inherit (lib) mkOption types mkIf;
in {
  options.services.sops-secrets-registry = {
    enable = mkOption {
      type = types.bool;
      default = false;
    };
    aiServices = mkOption {
      type = types.bool;
      default = false;
    };
    kubernetes = mkOption {
      type = types.bool;
      default = false;
    };
    cloud = mkOption {
      type = types.bool;
      default = false;
    };
    monitoring = mkOption {
      type = types.bool;
      default = false;
    };
    mining = mkOption {
      type = types.bool;
      default = false;
    };
    storage = mkOption {
      type = types.bool;
      default = false;
    };
    automation = mkOption {
      type = types.bool;
      default = false;
    };
    selfHosting = mkOption {
      type = types.bool;
      default = false;
    };
    ci = mkOption {
      type = types.bool;
      default = false;
    };
    cache = mkOption {
      type = types.bool;
      default = false;
    };
  };
  config = mkIf config.services.sops-secrets-registry.enable {
    sops = {
      defaultSopsFile = "${inputs.self}/secrets/ai/nvidia-api-key.yaml";
      defaultSopsFormat = "binary";
      age.keyFile = "/etc/nixos/.age/key.txt";
    };
    sops.secrets = {
      # NOTE: these are single-value sops files ({ "data": ENC[...] }),
      # so format must be "binary" — "yaml" makes sops-install-secrets
      # treat the secret name (storage/...) as a YAML key path and fail
      # with 'the key storage cannot be found' (deploy blocker 2026-08-13).
      "storage/garage-s3-access-key-id" = {
        sopsFile = "${inputs.self}/secrets/storage/garage-s3-access-key-id.yaml";
        format = "binary";
        owner = "root";
        group = "root";
        mode = "0440";
      };
      "storage/garage-s3-secret-key" = {
        sopsFile = "${inputs.self}/secrets/storage/garage-s3-secret-key.yaml";
        format = "binary";
        owner = "root";
        group = "root";
        mode = "0440";
      };
    };
  };
}

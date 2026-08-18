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
      defaultSopsFile = "${inputs.nixos-secrets}/secrets/ai/nvidia-api-key.yaml";
      defaultSopsFormat = "yaml";
      defaultSopsKey = "data";
      age.keyFile = "/etc/nixos/.age/key.txt";
    };
    sops.secrets = {
      # NOTE: these are single-value sops files (YAML envelope `data: ENC[...]`).
      # After the 2026-08-16 age-key rotation (`sops updatekeys` rewrote all
      # store files as YAML), format must be "yaml" with key = "data".
      # "binary" requires a JSON envelope and fails check-mode with
      # 'cannot parse json' (deploy blocker 2026-08-16).
      #
      # Secrets now live in the private nixos-secrets flake (git+ssh://git@github.com/reverb256/nixos-secrets).
      # This repo references them via ${inputs.nixos-secrets}/secrets/<path>.
      "storage/garage-s3-access-key-id" = {
        sopsFile = "${inputs.nixos-secrets}/secrets/storage/garage-s3-access-key-id.yaml";
        format = "yaml";
        key = "data";
        owner = "root";
        group = "root";
        mode = "0440";
      };
      "storage/garage-s3-secret-key" = {
        sopsFile = "${inputs.nixos-secrets}/secrets/storage/garage-s3-secret-key.yaml";
        format = "yaml";
        key = "data";
        owner = "root";
        group = "root";
        mode = "0440";
      };
      # Tailscale preauth key (declarative join; ignored once a node is joined).
      # Declared in secretspec.toml:177-178 as TAILSCALE_AUTH_KEY.
      "tailscale/authkey" = {
        sopsFile = "${inputs.nixos-secrets}/secrets/cloud/tailscale-oauth.yaml";
        format = "yaml";
        key = "data";
        owner = "root";
        group = "root";
        mode = "0400";
      };
    };
  };
}

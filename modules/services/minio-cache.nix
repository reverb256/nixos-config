{
  config,
  lib,
  ...
}: let
  cfg = config.services.nixos-minio-cache;
in {
  options.services.nixos-minio-cache = {
    enable = lib.mkEnableOption "MinIO S3 binary cache for Nix";

    endpoint = lib.mkOption {
      type = lib.types.str;
      description = "MinIO endpoint URL (e.g., http://localhost:9000 or https://minio.yourdomain.com)";
    };

    bucket = lib.mkOption {
      type = lib.types.str;
      default = "nix-cache";
      description = "S3 bucket name for the cache";
    };

    region = lib.mkOption {
      type = lib.types.str;
      default = "us-east-1";
      description = "S3 region (can be any value for MinIO)";
    };

    credentialsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to file containing MINIO_ACCESS_KEY and MINIO_SECRET_KEY";
    };

    publicKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Public key for signed cache (if using signed cache)";
    };

    privateKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to private key file for signing cache uploads";
    };
  };

  config = lib.mkIf cfg.enable {
    nix.settings = {
      # Add MinIO cache to substituters
      substituters = lib.mkAfter [
        "s3://${cfg.bucket}?endpoint=${cfg.endpoint}&region=${cfg.region}"
      ];

      # For signed caches, configure signing key
      secret-key-files = lib.mkIf (cfg.privateKeyFile != null) [cfg.privateKeyFile];
      trusted-public-keys = lib.mkIf (cfg.publicKey != null) [cfg.publicKey];
    };

    # Configure S3 credentials if provided
    systemd.services.nix-daemon.serviceConfig = lib.mkIf (cfg.credentialsFile != null) {
      EnvironmentFile = cfg.credentialsFile;
    };
  };
}

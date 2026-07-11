{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.aistor-secrets;
  # accessKey/secretKey are nullOr (default null) and only meaningful in
  # mode="custom". They are interpolated into the script at eval time, so a
  # bare ${cfg.accessKey} on a host with default-null keys would crash the
  # build (cannot coerce null to a string). Fall back to "" so the custom
  # branch is safe when unset; the runtime case only emits these in custom mode.
  accessKeyValue = if cfg.accessKey != null then cfg.accessKey else "";
  secretKeyValue = if cfg.secretKey != null then cfg.secretKey else "";
in {
  options.services.aistor-secrets = {
    enable = lib.mkEnableOption "Generate and manage AIStor (MinIO) credentials declaratively";

    mode = lib.mkOption {
      type = lib.types.enum ["demo" "generate" "custom"];
      default = "generate";
      description = ''
        How to handle credentials:
        - demo: Use minioadmin/minioadmin (NOT SECURE for production!)
        - generate: Generate secure random credentials
        - custom: Use explicit credentials (via options below)
      '';
    };

    accessKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Custom access key (only for mode=custom)";
    };

    secretKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Custom secret key (only for mode=custom)";
    };

    outputPath = lib.mkOption {
      type = lib.types.path;
      default = "/tmp/aistor-credentials.env";
      description = "Where to write credentials file";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.aistor-generate-credentials = {
      description = "Generate AIStor credentials declaratively";
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "aistor-generate-credentials" ''
                    ${pkgs.coreutils}/bin/mkdir -p "$(dirname ${cfg.outputPath})"

                    case "${cfg.mode}" in
                      demo)
                        ${pkgs.coreutils}/bin/cat > ${cfg.outputPath} << 'EOF'
          MINIO_ACCESS_KEY=minioadmin
          MINIO_SECRET_KEY=minioadmin
          EOF
                        ;;
                      generate)
                        ACCESS_KEY="$(${pkgs.coreutils}/bin/tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20)"
                        SECRET_KEY="$(${pkgs.coreutils}/bin/tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)"
                        ${pkgs.coreutils}/bin/cat > ${cfg.outputPath} << EOF
          MINIO_ACCESS_KEY=$ACCESS_KEY
          MINIO_SECRET_KEY=$SECRET_KEY
          EOF
                        ;;
                      custom)
                        ${pkgs.coreutils}/bin/cat > ${cfg.outputPath} << EOF
          MINIO_ACCESS_KEY=${accessKeyValue}
          MINIO_SECRET_KEY=${secretKeyValue}
          EOF
                        ;;
                    esac

                    ${pkgs.coreutils}/bin/chmod 600 ${cfg.outputPath}
        '';

        StandardOutput = "journal";
        StandardError = "journal";
      };
    };
  };
}

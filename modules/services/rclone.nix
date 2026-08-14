{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.rclone-sync;

  # ═══════════════════════════════════════════════════════════════════════════
  # rclone.conf generator
  # ═══════════════════════════════════════════════════════════════════════════
  # Converts cfg.remotes (attrset of remote name → remote options) into an
  # INI-style rclone.conf. Credential fields left as "" in the Nix declaration
  # are emitted as "_" so rclone falls back to environment variables.
  #
  # Environment variables are supplied at runtime via:
  #   1. cfg.preRun  — extra env vars per job (VAR=value)
  #   2. job.sopsSecretEnvs — maps sops-decrypted /run/secrets/* files to
  #      env vars inline in the sync script

  fieldsForRemote = remote: let
    f = key: value:
      if value != null && value != ""
      then ["${key} = ${value}"]
      else ["${key} = _"];

    common = ["type = ${remote.type}"];

    s3 =
      lib.optional (remote.provider != null && remote.provider != "")
      "provider = ${remote.provider}"
      ++ lib.optional (remote.endpoint != null && remote.endpoint != "")
      "endpoint = ${remote.endpoint}"
      ++ f "access_key_id" remote.accessKeyId
      ++ f "secret_access_key" remote.secretAccessKey
      ++ ["region = ${remote.region or "us-east-1"}"]
      ++ lib.optional (remote.forcePathStyle) "force_path_style = true";

    tokenOpt = remote.token;
    oauthToken =
      if tokenOpt != null && tokenOpt != ""
      then ["token = ${tokenOpt}"]
      else ["token = _"];

    b2 =
      f "account" remote.account
      ++ f "key" remote.key;

    drive =
      f "client_id" remote.client_id
      ++ f "client_secret" remote.client_secret
      ++ (
        if remote.scope != null && remote.scope != ""
        then ["scope = ${remote.scope}"]
        else []
      );

    mega =
      f "user" remote.user
      ++ f "pass" remote.pass;

    ftpSftp =
      f "user" remote.user
      ++ f "pass" remote.pass;

    webdav =
      lib.optional (remote.endpoint != null && remote.endpoint != "")
      "url = ${remote.endpoint}";

    box =
      f "client_id" remote.client_id
      ++ f "client_secret" remote.client_secret;

    # Fields per backend (excluding the common `type` line, prepended below).
    # `http` shares webdav's shape (url = endpoint).
    perType = {
      s3 = s3;
      onedrive = oauthToken;
      dropbox = oauthToken;
      b2 = b2;
      drive = drive;
      mega = mega;
      ftp = ftpSftp;
      sftp = ftpSftp;
      webdav = webdav;
      box = box;
      http = webdav;
    };
  in
    # rclone requires `type = ...` in every section; previously `common` was
    # dead code and no section ever emitted its type line, so every remote
    # would fail at runtime. Always prepend it.
    builtins.concatStringsSep "\n" (common ++ (perType.${remote.type} or []));

  remoteSection = name: let
    # fieldsForRemote returns the fully joined INI body string for this
    # remote (type line + backend fields). (Previously it returned a raw
    # LIST, which made every rclone-enabled host fail with "cannot coerce a
    # list to a string" when interpolated.)
    body = fieldsForRemote cfg.remotes.${name};
  in "[${name}]\n${body}";

  rcloneConfigText = builtins.concatStringsSep "\n\n" (
    builtins.map remoteSection (builtins.attrNames cfg.remotes)
  );

  # ═══════════════════════════════════════════════════════════════════════════
  # sync script generator
  # ═══════════════════════════════════════════════════════════════════════════
  # Wraps the rclone invocation. If the job declares sopsSecretEnvs, each
  # entry reads a sops-decrypted file from /run/secrets/ and exports it as an
  # env var inline, before the rclone invocation.

  syncScript = job: let
    secretExports = lib.concatStringsSep "\n" (
      map (
        s: ''
          if [ -f ${s.secretPath} ]; then
            export ${s.var}="$(cat ${s.secretPath})"
          else
            echo "rclone-${job.name}: missing secret ${s.secretPath}" >&2
            exit 1
          fi
        ''
      )
      job.sopsSecretEnvs
    );
  in
    pkgs.writeShellScriptBin "rclone-${job.name}" ''
      set -euo pipefail

      SOURCE=''${SOURCE:-${job.source}}
      DEST=''${DEST:-${job.destination}}
      SYNC_MODE=''${SYNC_MODE:-${job.mode or "sync"}}
      OPTIONS=''${OPTIONS:-${toString job.options or ""}}

      RED='\033[0;31m'
      GREEN='\033[0;32m'
      YELLOW='\033[1;33m'
      BLUE='\033[0;34m'
      NC='\033[0m'

      log_info() { echo -e ''${BLUE}[INFO]''${NC} $1; }
      log_success() { echo -e ''${GREEN}[SUCCESS]''${NC} $1; }
      log_warn() { echo -e ''${YELLOW}[WARN]''${NC} $1; }
      log_error() { echo -e ''${RED}[ERROR]''${NC} $1; }

      ${secretExports}

      log_info "Starting rclone job: ${job.name}"
      log_info "Source: $SOURCE"
      log_info "Destination: $DEST"
      log_info "Mode: $SYNC_MODE"

      if ${pkgs.rclone}/bin/rclone "$SYNC_MODE" "$SOURCE" "$DEST" \
        --config "${cfg.configFile}" \
        --progress \
        --transfers ${toString job.transfers or 4} \
        --checkers ${toString job.checkers or 8} \
        ${
        if job.exclude != null
        then "--exclude=${job.exclude}"
        else ""
      } \
        ${
        if job.excludeFrom != null
        then "--exclude-from=${job.excludeFrom}"
        else ""
      } \
        ${
        if job.include != null
        then "--include=${job.include}"
        else ""
      } \
        ${
        if job.includeFrom != null
        then "--include-from=${job.includeFrom}"
        else ""
      } \
        ${lib.concatStringsSep " " (map (o: "--${o}") (job.extraFlags or []))} \
        $OPTIONS; then
        log_success "Job '${job.name}' completed"
      else
        log_error "Job '${job.name}' failed"
        exit 1
      fi
    '';
in {
  options.services.rclone-sync = {
    enable = lib.mkEnableOption "Rclone cloud storage synchronization";

    configFile = lib.mkOption {
      type = lib.types.path;
      default = "/etc/rclone/rclone.conf";
      description = "Path to rclone configuration file";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "User to run rclone services as";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "Group to run rclone services as";
    };

    # Environment variables set before each rclone job (VAR=value form).
    # For non-sops env vars. sops secrets go through sopsSecretEnvs below.
    preRun = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Extra environment variables per rclone job (VAR=value)";
    };

    remotes = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            type = lib.mkOption {
              type = lib.types.enum [
                "s3"
                "onedrive"
                "dropbox"
                "box"
                "mega"
                "b2"
                "drive"
                "webdav"
                "ftp"
                "sftp"
                "http"
              ];
              default = "s3";
              description = "Remote storage type";
            };
            provider = lib.mkOption {
              type = lib.types.str;
              default = "Other";
              description = "S3 provider (AWS, Other, Minio, etc.)";
            };
            endpoint = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "S3 endpoint URL / webdav base URL";
            };
            accessKeyId = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Access key ID for S3";
            };
            secretAccessKey = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Secret access key for S3 — leave empty, supply via sopsSecretEnvs";
            };
            region = lib.mkOption {
              type = lib.types.str;
              default = "us-east-1";
              description = "S3 region";
            };
            forcePathStyle = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Force path-style S3 URLs";
            };
            token = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "OAuth token (onedrive, dropbox, etc.)";
            };
            user = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Username (mega, ftp, sftp)";
            };
            pass = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Password (mega, ftp, sftp)";
            };
            account = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Account ID (B2)";
            };
            key = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Application key (B2)";
            };
            client_id = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "OAuth client ID (drive, box)";
            };
            client_secret = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "OAuth client secret (drive, box)";
            };
            scope = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "OAuth scope (drive)";
            };
          };
        }
      );
      default = {};
      description = "Remote storage configurations";
      example = {
        garage = {
          type = "s3";
          provider = "Other";
          endpoint = "http://${config.networking.cluster.hosts.zephyr.ip}:3900";
          region = "garage";
        };
      };
    };

    syncJobs = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Job name (used for service/timer names)";
            };
            source = lib.mkOption {
              type = lib.types.str;
              description = "Source path (remote: or /local/path)";
            };
            destination = lib.mkOption {
              type = lib.types.str;
              description = "Destination path (remote: or /local/path)";
            };
            mode = lib.mkOption {
              type = lib.types.enum [
                "sync"
                "copy"
                "move"
                "check"
                "ls"
                "lsl"
                "lsd"
                "lsf"
              ];
              default = "sync";
              description = "Rclone operation mode";
            };
            transfers = lib.mkOption {
              type = lib.types.int;
              default = 4;
              description = "Number of parallel file transfers";
            };
            checkers = lib.mkOption {
              type = lib.types.int;
              default = 8;
              description = "Number of checkers to run in parallel";
            };
            exclude = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Exclude files matching pattern";
            };
            excludeFrom = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = "Read exclude patterns from file";
            };
            include = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Include files matching pattern";
            };
            includeFrom = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = "Read include patterns from file";
            };
            options = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Additional options string";
            };
            extraFlags = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              description = "Extra command-line flags (without -- prefix)";
            };
            enableTimer = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable systemd timer for automated execution";
            };
            startAt = lib.mkOption {
              type = lib.types.str;
              default = "02:00";
              description = "When to run (systemd timer calendar format)";
            };
            # sopsSecretEnvs: map sops-decrypted secret files to env vars.
            # Each entry reads the file at secretPath and exports it as var.
            # Files are under /run/secrets/ (populated by sops-nix at activation).
            sopsSecretEnvs = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    var = lib.mkOption {
                      type = lib.types.str;
                      description = "Environment variable name to export";
                    };
                    secretPath = lib.mkOption {
                      type = lib.types.str;
                      description = "Absolute path to sops-decrypted secret file (e.g. /run/secrets/storage/garage-s3-secret-key)";
                    };
                  };
                }
              );
              default = [];
              description = "Sops secret → environment variable mappings for this job";
            };
          };
        }
      );
      default = [];
      description = "Sync job definitions";
      example = [
        {
          name = "garage-backup-verify";
          source = "garage:";
          destination = "garage:";
          mode = "ls";
          startAt = "03:00";
          enableTimer = true;
          sopsSecretEnvs = [
            {
              var = "AWS_SECRET_ACCESS_KEY";
              secretPath = "/run/secrets/storage/garage-s3-secret-key";
            }
          ];
        }
      ];
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [pkgs.rclone];

    environment.etc."rclone/rclone.conf" = {
      text = rcloneConfigText;
      mode = "0400";
      user = "root";
      group = "root";
    };

    systemd.services = lib.listToAttrs (
      map (job: {
        name = "rclone-${job.name}";
        value = {
          description = "Rclone sync: ${job.name}";
          after = ["network-online.target"];
          wants = ["network-online.target"];
          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            Group = cfg.group;
            ExecStart = "${syncScript job}/bin/rclone-${job.name}";
            Environment =
              ["PATH=/run/current-system/sw/bin" "RCLONE_CONFIG=${cfg.configFile}"]
              ++ cfg.preRun;
            PrivateTmp = true;
            NoNewPrivileges = true;
            RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
            SystemCallFilter = ["@system-service" "~@privileged"];
          };
        };
      })
      cfg.syncJobs
    );

    systemd.timers = lib.listToAttrs (
      map (job: {
        name = "rclone-${job.name}";
        value =
          # NOTE: previously had `inherit (job) enableTimer;` here, which
          # pushed an `enableTimer` key into the systemd.timers.<name> value.
          # systemd.timers has NO such option — it made every enabled job
          # fail evaluation with "option `systemd.timers.rclone-*.enableTimer'
          # does not exist". The enable wiring lives in the optionalAttrs
          # branch below (wantedBy + timerConfig), so this was dead weight.
          lib.optionalAttrs job.enableTimer {
            wantedBy = ["timers.target"];
            timerConfig = {
              OnCalendar = job.startAt;
              Persistent = true;
              Unit = "rclone-${job.name}.service";
            };
          };
      })
      cfg.syncJobs
    );
  };
}

# Custom Storage Module for NixOS
# Handles both local and remote (rclone) storage configurations
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.storage;
in {
  options.storage = {
    # Local storage options
    local = {
      enable = mkEnableOption "local storage configurations";

      filesystems = mkOption {
        type = types.attrsOf (types.submodule {
          options = {
            device = mkOption {type = types.str;};
            fsType = mkOption {type = types.str;};
            options = mkOption {
              type = types.listOf types.str;
              default = ["defaults"];
            };
            mountPoint = mkOption {type = types.str;};
            autoFormat = mkEnableOption "auto-format filesystem on first boot";
            label = mkOption {
              type = types.nullOr types.str;
              default = null;
            };
          };
        });
        default = {};
        description = "Declarative filesystem mounts";
      };

      zfs = {
        enable = mkEnableOption "ZFS support";
        pools = mkOption {
          type = types.attrsOf (types.submodule {
            options = {
              devices = mkOption {type = types.listOf types.str;};
              mountpoint = mkOption {
                type = types.nullOr types.str;
                default = null;
              };
              properties = mkOption {
                type = types.attrsOf types.str;
                default = {};
              };
            };
          });
          default = {};
        };
      };

      btrfs = {
        enable = mkEnableOption "Btrfs support";
        subvolumes = mkOption {
          type = types.attrsOf (types.submodule {
            options = {
              device = mkOption {type = types.str;};
              subvol = mkOption {type = types.str;};
              mountPoint = mkOption {type = types.str;};
              options = mkOption {
                type = types.listOf types.str;
                default = ["defaults"];
              };
            };
          });
          default = {};
        };
      };
    };

    # Remote storage options (rclone)
    remote = {
      enable = mkEnableOption "remote storage configurations";

      rclone = {
        enable = mkEnableOption "rclone mounts and backups";

        # Declarative rclone configuration
        config = mkOption {
          type = types.attrsOf (types.attrsOf types.str);
          default = {};
          example = {
            gdrive = {
              type = "drive";
              scope = "drive";
              token = "{...}";
            };
          };
          description = "Declarative rclone remote configurations";
        };

        user = mkOption {
          type = types.str;
          default = "root";
          description = "User to run rclone mounts as";
        };

        mounts = mkOption {
          type = types.attrsOf (types.submodule {
            options = {
              remote = mkOption {
                type = types.str;
                description = "Rclone remote name";
              };
              mountPoint = mkOption {
                type = types.str;
                description = "Local mount point";
              };
              options = mkOption {
                type = types.listOf types.str;
                default = ["--allow-other" "--vfs-cache-mode" "writes"];
                description = "Additional rclone mount options";
              };
              daemon = mkOption {
                type = types.bool;
                default = true;
                description = "Run rclone in daemon mode";
              };
            };
          });
          default = {};
          description = "Rclone remote mounts";
        };

        # Backup configurations
        backups = mkOption {
          type = types.attrsOf (types.submodule {
            options = {
              source = mkOption {type = types.str;};
              remote = mkOption {type = types.str;};
              schedule = mkOption {
                type = types.str;
                default = "daily";
                description = "Backup schedule (systemd timer format)";
              };
              options = mkOption {
                type = types.listOf types.str;
                default = ["--progress" "--log-file=/var/log/rclone-backup.log"];
              };
            };
          });
          default = {};
        };

        # Nexus backup configurations (excluding OneDrive due to Personal Vault issues)
        nexus-backups = mkOption {
          type = types.attrsOf (types.submodule {
            options = {
              source = mkOption {type = types.str;};
              remote = mkOption {
                type = types.str;
                default = "nexus";
              };
              path = mkOption {
                type = types.str;
                description = "Path on nexus to backup to";
              };
              schedule = mkOption {
                type = types.str;
                default = "daily";
                description = "Backup schedule (systemd timer format)";
              };
              options = mkOption {
                type = types.listOf types.str;
                default = [
                  "--progress"
                  "--log-file=/var/log/rclone-backup.log"
                  "--transfers=4"
                  "--checkers=8"
                ];
              };
            };
          });
          default = {};
          description = "Rclone backup configurations to nexus (excluding OneDrive)";
        };
      };

      # Other remote storage backends could be added here
      # e.g., sshfs, nfs, etc.
    };
  };

  config = mkMerge [
    # Local storage configuration
    (mkIf cfg.local.enable {
      # Enable filesystem utilities
      environment.systemPackages = with pkgs; [
        ntfs3g # NTFS support
        exfat # exFAT support
        btrfs-progs
        zfs
      ];

      # Configure filesystems
      fileSystems =
        mapAttrs' (
          _name: fsCfg:
            nameValuePair fsCfg.mountPoint {
              inherit (fsCfg) device;
              inherit (fsCfg) fsType;
              inherit (fsCfg) options;
              # Add auto-format logic if enabled
              inherit (fsCfg) autoFormat label;
            }
        )
        cfg.local.filesystems;

      # ZFS configuration
      boot = mkIf cfg.local.zfs.enable {
        supportedFilesystems = ["zfs"];
        zfs.requestEncryptionCredentials = true;
      };

      services.zfs = mkIf cfg.local.zfs.enable {
        autoScrub.enable = true;
        autoSnapshot.enable = true;
      };

      # Btrfs configuration
      services.btrfs.autoScrub = mkIf cfg.local.btrfs.enable {
        enable = true;
        fileSystems = attrNames cfg.local.btrfs.subvolumes;
      };
    })

    # Remote storage configuration - Rclone
    (mkIf (cfg.remote.enable && cfg.remote.rclone.enable) {
      # Ensure FUSE is available
      boot.kernelModules = ["fuse"];

      environment.systemPackages = with pkgs; [
        rclone
        fuse
      ];

      # Generate declarative rclone config file
      environment.etc."rclone/rclone.conf" = mkIf (cfg.remote.rclone.config != {}) {
        text = concatStringsSep "\n" (
          mapAttrsToList (
            name: config:
              "[${name}]\n"
              + concatStringsSep "\n" (
                mapAttrsToList (key: value: "${key} = ${value}") config
              )
          )
          cfg.remote.rclone.config
        );
      };

      # Systemd configuration for rclone
      systemd = {
        # Create mount point directories
        tmpfiles.rules =
          mapAttrsToList (
            _name: mountCfg: "d ${mountCfg.mountPoint} 0755 ${cfg.remote.rclone.user} users -"
          )
          cfg.remote.rclone.mounts;

        # Rclone services (mounts and backups)
        services = mkMerge [
          # Mount services
          (mapAttrs' (
              name: mountCfg:
                nameValuePair "rclone-mount-${name}" {
                  description = "RClone mount for ${name}";
                  after = ["network-online.target"];
                  wants = ["network-online.target"];
                  serviceConfig = {
                    Type = "oneshot";
                    User = cfg.remote.rclone.user;
                    ExecStart =
                      "${pkgs.rclone}/bin/rclone mount ${mountCfg.remote}: ${mountCfg.mountPoint} "
                      + (
                        if mountCfg.daemon
                        then "--daemon "
                        else ""
                      )
                      + (concatStringsSep " " mountCfg.options);
                    RemainAfterExit = true;
                    ExecStop = "${pkgs.fuse}/bin/fusermount -u ${mountCfg.mountPoint}";
                  };
                  wantedBy = ["multi-user.target"];
                }
            )
            cfg.remote.rclone.mounts)

          # Backup services
          (mapAttrs' (
              name: backupCfg:
                nameValuePair "rclone-backup-${name}" {
                  description = "RClone backup for ${name}";
                  serviceConfig = {
                    Type = "oneshot";
                    User = cfg.remote.rclone.user;
                    ExecStart =
                      "${pkgs.rclone}/bin/rclone copy ${backupCfg.source} ${backupCfg.remote}: "
                      + (concatStringsSep " " backupCfg.options);
                  };
                }
            )
            cfg.remote.rclone.backups)

          # Nexus backup services
          (mapAttrs' (
              name: backupCfg:
                nameValuePair "rclone-nexus-backup-${name}" {
                  description = "RClone backup ${name} to nexus";
                  serviceConfig = {
                    Type = "oneshot";
                    User = cfg.remote.rclone.user;
                    ExecStart =
                      "${pkgs.rclone}/bin/rclone copy ${backupCfg.source} ${backupCfg.remote}:${backupCfg.path} "
                      + (concatStringsSep " " backupCfg.options);
                    TimeoutStartSec = 7200; # 2 hour timeout for large transfers
                    TimeoutStopSec = 30;
                    Restart = "on-failure";
                    RestartSec = 300; # 5 minute restart delay
                  };
                }
            )
            cfg.remote.rclone.nexus-backups)
        ];

        # Backup timers
        timers = mkMerge [
          (mapAttrs' (
              name: backupCfg:
                nameValuePair "rclone-backup-${name}" {
                  description = "Timer for rclone backup ${name}";
                  wantedBy = ["timers.target"];
                  timerConfig = {
                    OnCalendar = backupCfg.schedule;
                    Persistent = true;
                  };
                }
            )
            cfg.remote.rclone.backups)

          # Nexus backup timers
          (mapAttrs' (
              name: backupCfg:
                nameValuePair "rclone-nexus-backup-${name}" {
                  description = "Timer for rclone backup ${name} to nexus";
                  wantedBy = ["timers.target"];
                  timerConfig = {
                    OnCalendar = backupCfg.schedule;
                    Persistent = true;
                  };
                }
            )
            cfg.remote.rclone.nexus-backups)
        ];
      };
    })
  ];
}

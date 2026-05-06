{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.btrfs-boot-snapshot;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.btrfs-boot-snapshot = {
    enable = mkEnableOption "Pre-boot BTRFS snapshot and rollback helper";

    subvolume = mkOption {
      type = types.str;
      default = "@";
      description = "Root BTRFS subvolume name (e.g. '@')";
    };

    device = mkOption {
      type = types.str;
      description = "BTRFS device path or UUID (e.g. /dev/disk/by-uuid/...)";
    };

    snapshotRetention = mkOption {
      type = types.int;
      default = 10;
      description = "Number of boot snapshots to keep";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.services.initrd-ssh-recovery.enable;
        message = "btrfs-boot-snapshot requires initrd-ssh-recovery to be enabled";
      }
    ];

    # Systemd service: create a boot-time snapshot
    systemd.services.btrfs-boot-snapshot = {
      description = "Create BTRFS snapshot of root subvolume";
      after = ["local-fs.target"];
      wantedBy = ["multi-user.target"];
      path = with pkgs; [btrfs-progs coreutils util-linux];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail

        DEV="${cfg.device}"
        SUBVOL="${cfg.subvolume}"
        RETENTION=${toString cfg.snapshotRetention}
        SNAPDIR=".snapshots"

        MNT=$(mktemp -d)
        mount -t btrfs -o subvol=/ "$DEV" "$MNT"

        mkdir -p "$MNT/$SNAPDIR"

        TIMESTAMP=$(date +%Y%m%d-%H%M%S)
        SNAPNAME="boot-''${TIMESTAMP}"
        echo "Creating snapshot: $SNAPNAME"
        btrfs subvolume snapshot "$MNT/$SUBVOL" "$MNT/$SNAPDIR/$SNAPNAME"

        COUNT=$(ls -1d "$MNT/$SNAPDIR"/boot-* 2>/dev/null | wc -l)
        if [ "$COUNT" -gt "$RETENTION" ]; then
          PRUNE=$(ls -1d "$MNT/$SNAPDIR"/boot-* | head -n $((COUNT - RETENTION)))
          echo "Pruning $((COUNT - RETENTION)) old snapshots:"
          echo "$PRUNE" | while read -r old; do
            btrfs subvolume delete "$old"
          done
        fi

        umount "$MNT"
        rmdir "$MNT"
        echo "Boot snapshot complete."
      '';
    };

    # Rollback helper script
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "btrfs-rollback" ''
        set -euo pipefail

        if [ $# -lt 1 ]; then
          echo "Usage: btrfs-rollback <snapshot-name|latest>"
          echo ""
          echo "Snapshots live in .snapshots/ on the BTRFS toplevel."
          echo "Examples:"
          echo "  btrfs-rollback latest"
          echo "  btrfs-rollback boot-20260505-080000"
          exit 1
        fi

        DEV="${cfg.device}"
        SUBVOL="${cfg.subvolume}"
        SNAPDIR=".snapshots"
        TARGET="$1"

        MNT=$(mktemp -d)
        mount -t btrfs -o subvol=/ "$DEV" "$MNT"

        if [ "$TARGET" = "latest" ]; then
          TARGET=$(ls -1d "$MNT/$SNAPDIR"/boot-* 2>/dev/null | sort | tail -1)
          if [ -z "$TARGET" ]; then
            echo "ERROR: No snapshots found"
            umount "$MNT"; rmdir "$MNT"
            exit 1
          fi
        else
          TARGET="$MNT/$SNAPDIR/$TARGET"
        fi

        SNAPNAME=$(basename "$TARGET")
        echo "Rolling back to: $SNAPNAME"
        echo "Removing current $SUBVOL..."
        btrfs subvolume delete "$MNT/$SUBVOL"
        echo "Restoring from $SNAPNAME..."
        btrfs subvolume snapshot "$TARGET" "$MNT/$SUBVOL"

        echo "Rollback complete. Reboot to apply."
        umount "$MNT"; rmdir "$MNT"
        echo "Run: systemctl reboot"
      '')
    ];
  };
}

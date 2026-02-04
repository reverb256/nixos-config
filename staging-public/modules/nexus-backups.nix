_: {
  # ============================================================================
  # NEXUS BACKUP CONFIGURATIONS (excluding OneDrive)
  # ============================================================================

  # Configure rclone mounts and backups to nexus
  storage.remote.rclone = {
    enable = true;
    user = "j_kro";

    # Configure nexus remote mount (if needed for verification)
    mounts = {
      nexus = {
        remote = "WORKER_X";
        mountPoint = "/mnt/nexus-remote";
        options = [
          "--allow-other"
          "--vfs-cache-mode"
          "writes"
          "--vfs-cache-max-size"
          "10G"
        ];
        daemon = true;
      };
    };

    # Backup configurations to nexus (excluding OneDrive due to Personal Vault)
    nexus-backups = {
      # Google Drive backup to nexus
      "gdrive-backup" = {
        source = "gdrive:/Backups";
        path = "/gdrive-backups";
        schedule = "daily";
        options = [
          "--progress"
          "--log-file=/var/log/rclone-backup-gdrive.log"
          "--transfers=4"
          "--checkers=8"
          "--size-limit=10G" # Skip very large files that might cause timeouts
        ];
      };

      # Dropbox backup to nexus
      "dropbox-backup" = {
        source = "dropbox:/";
        path = "/dropbox-backups";
        schedule = "daily";
        options = [
          "--progress"
          "--log-file=/var/log/rclone-backup-dropbox.log"
          "--transfers=4"
          "--checkers=8"
        ];
      };

      # MEGA backup to nexus (excluding OneDrive duplicates)
      "mega-backup" = {
        source = "mega:/";
        path = "/mega-backups";
        schedule = "daily";
        options = [
          "--progress"
          "--log-file=/var/log/rclone-backup-mega.log"
          "--transfers=4"
          "--checkers=8"
        ];
      };

      # Box backup to nexus
      "box-backup" = {
        source = "box:/";
        path = "/box-backups";
        schedule = "daily";
        options = [
          "--progress"
          "--log-file=/var/log/rclone-backup-box.log"
          "--transfers=4"
          "--checkers=8"
        ];
      };

      # pCloud backup to nexus
      "pcloud-backup" = {
        source = "pcloud:/";
        path = "/pcloud-backups";
        schedule = "daily";
        options = [
          "--progress"
          "--log-file=/var/log/rclone-backup-pcloud.log"
          "--transfers=4"
          "--checkers=8"
        ];
      };
    };
  };
}

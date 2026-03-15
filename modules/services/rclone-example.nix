# Rclone Cloud Storage Sync - Usage Examples

## Overview

The `rclone-sync` module provides declarative rclone configuration with support for 70+ cloud providers.

## Supported Providers

- **S3-compatible:** AWS S3, Garage S3, MinIO, Wasabi, Backblaze B2
- **Cloud Storage:** Google Drive, OneDrive, Dropbox, Box, Mega, pCloud
- **Protocols:** WebDAV, FTP, SFTP, HTTP

## Basic Configuration

### Enable in Host Configuration

```nix
# hosts/zephyr/configuration.nix
{ ... }: {
  services.rclone-sync = {
    enable = true;

    # Define remotes
    remotes = {
      # Garage S3 cluster
      garage = {
        type = "s3";
        provider = "Other";
        endpoint = "http://10.1.1.110:3900";
        accessKeyId = "GKac91d924fc76a30b9bcf6c3e";
        secretAccessKey = "your-secret-key";  # Use agenix!
        region = "garage";
      };
    };
  };
}
```

### With Agenix Secret (Recommended)

```nix
# hosts/zephyr/configuration.nix
{ ... }: {
  services.rclone-sync = {
    enable = true;

    remotes = {
      garage = {
        type = "s3";
        provider = "Other";
        endpoint = "http://10.1.1.110:3900";
        accessKeyId = "GKac91d924fc76a30b9bcf6c3e";
        secretAccessKey = "";  # Set via agenix!
        region = "garage";
      };
    };
  };

  # Agenix secret for Garage S3 key
  age.secrets.garage-s3-key = {
    file = "${inputs.self}/secrets/garage-s3-key.age";
    mode = "440";
    owner = "root";
  };

  # Pass secret to rclone (via systemd service environment)
  systemd.services.rclone-garage-backup.serviceConfig.EnvironmentFile =
    "/run/agenix/garage-s3-key";
}
```

## Sync Jobs

### Manual Backup to Cloud

```nix
services.rclone-sync = {
  enable = true;

  remotes = {
    garage = {
      type = "s3";
      provider = "Other";
      endpoint = "http://10.1.1.110:3900";
      accessKeyId = "GKac91d924fc76a30b9bcf6c3e";
      secretAccessKey = "";
      region = "garage";
    };
  };

  # Define automated sync jobs
  syncJobs = [
    {
      name = "garage-to-onedrive";
      source = "garage:backups";
      destination = "onedrive:garage-backups";
      mode = "sync";
      startAt = "03:00";  # Run at 3 AM daily
      enableTimer = true;
    }
  ];
};
```

### Two-Way Sync (Local ↔ Cloud)

```nix
syncJobs = [
  {
    name = "sync-docs-to-gdrive";
    source = "/data/documents";
    destination = "gdrive:documents";
    mode = "sync";
    startAt = "04:00";
  }
];
```

### Backup with Exclusions

```nix
syncJobs = [
  {
    name = "backup-projects-excluding-tmp";
    source = "/data/projects";
    destination = "garage:projects-backup";
    mode = "sync";
    exclude = ".tmp/**";
    excludeFrom = "/etc/rclone/exclude.txt";
    extraFlags = [ "delete-after" "dry-run" ];  # Safety first!
  }
];
```

## Cloud Provider Setup

### OneDrive

First, authenticate interactively (one-time):

```bash
rclone config
# > n (new remote)
# > Name: onedrive
# > Type: onedrive
# > Follow OAuth flow in browser
```

Then add the token to your configuration:

```nix
remotes.onedrive = {
  type = "onedrive";
  token = "{paste_token_from_rclone_config}";
};
```

### Dropbox

```bash
rclone config
# > n (new remote)
# > Name: dropbox
# > Type: dropbox
# > Follow OAuth flow
```

### Google Drive

```bash
rclone config
# > n (new remote)
# > Name: gdrive
# > Type: drive
# > Scope: 1 (Full access)
# > Follow OAuth flow
```

### Mega

```bash
rclone config
# > n (new remote)
# > Name: mega
# > Type: mega
# > Enter username/password
```

## Common Sync Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `sync` | Make source and dest identical, changing dest only | Backup to cloud |
| `copy` | Copy files from source to dest, skipping existing | Initial backup |
| `move` | Move files from source to dest | Archival |
| `check` | Check source and dest files match | Verification |
| `ls` | List all files in source | Inspection |

## Testing Before Deployment

Always test with dry-run first:

```bash
# Test connection
rclone ls garage:

# Dry-run sync (no changes)
rclone sync garage:backups onedrive:garage-backups --dry-run

# Actual sync
rclone sync garage:backups onedrive:garage-backups
```

## Systemd Management

```bash
# List all rclone timers
systemctl list-timers 'rclone-*'

# Run a job immediately
systemctl start rclone-garage-to-onedrive.service

# View job logs
journalctl -u rclone-garage-to-onedrive -f

# Enable/disable timer
systemctl enable rclone-garage-to-onedrive.timer
systemctl disable rclone-garage-to-onedrive.timer
```

## Security Best Practices

1. **Always use agenix for secrets:** Never hardcode passwords/tokens
2. **Start with dry-run:** Test sync jobs before enabling
3. **Use specific remotes:** Don't sync entire filesystems
4. **Set appropriate schedules:** Avoid peak hours for large transfers
5. **Monitor logs:** Check journalctl for errors regularly

## Troubleshooting

### Connection Failed

```bash
# Test remote connectivity
rclone ls garage:

# Check firewall
sudo iptables -L -n | grep 3900  # Garage S3 API port
```

### Authentication Errors

```bash
# Verify credentials
cat /etc/rclone/rclone.conf

# Re-authenticate if needed
rclone config reconnect onedrive
```

### Permission Denied

```bash
# Check file ownership
ls -la /data/projects

# Ensure rclone runs as correct user
systemctl show rclone-sync-job | grep User
```

## Migration from Manual Config

If you have an existing `~/.config/rclone/rclone.conf`:

```bash
# View current config
cat ~/.config/rclone/rclone.conf

# Copy secrets to agenix
agenix -e secrets/rclone-garage.age

# Update NixOS config to use declarative format
# Deploy: just deploy
```

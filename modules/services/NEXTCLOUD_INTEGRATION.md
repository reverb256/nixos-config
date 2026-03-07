# Synapse + Nextcloud Integration Guide

This guide shows how to integrate your **Synapse AI Command Center** with **Nextcloud** for a unified self-hosted productivity and AI stack.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                        Your NixOS Host                           │
├──────────────────────────────────────────────────────────────────┤
│                                                                    │
│  ┌────────────────────┐          ┌────────────────────┐          │
│  │   Synapse          │          │   Nextcloud        │          │
│  │  (AI Command       │ <──────> │  (Files & Collab)  │          │
│  │   Center)          │  WebDAV  │                    │          │
│  │                    │          │                    │          │
│  │  - Agent logs      │ Export   │  - /Synapse/       │          │
│  │  - Conversations   │ ────────>│  - Agent-Logs/     │          │
│  │  - Artifacts       │          │  - Projects/       │          │
│  └────────────────────┘          │  - Archive/        │          │
│           │                      └────────────────────┘          │
│           │                         │         │                 │
│           v                         v         v                 │
│  ┌────────────────────┐    ┌──────────┐  ┌──────────┐          │
│  │   vLLM / CC        │    │  Deck    │  │  Talk    │          │
│  │   Router           │    │ (Kanban) │  │ (Video)  │          │
│  └────────────────────┘    └──────────┘  └──────────┘          │
│                                                                  │
│  Shared: PostgreSQL + Redis                                      │
└──────────────────────────────────────────────────────────────────┘
```

---

## Integration Patterns

### 1. WebDAV Integration (File Export)

Synapse can export agent logs and conversation history directly to Nextcloud via WebDAV:

```typescript
// In Synapse: src/services/nextcloud-exporter.ts
import { createClient } from 'webdav'

const nextcloudClient = createClient(
  'https://cloud.zephyr.local/remote.php/webdav/',
  {
    username: process.env.NEXTCLOUD_USER,
    password: process.env.NEXTCLOUD_PASSWORD
  }
)

// Export agent logs to Nextcloud
async function exportAgentLog(agentId: string, logs: string[]) {
  const date = new Date().toISOString().split('T')[0]
  const path = `/Synapse/Agent-Logs/${agentId}/${date}.json`
  await nextcloudClient.putFileContents(path, JSON.stringify(logs, null, 2))
}

// Export conversation history
async function exportConversation(conversationId: string, messages: Message[]) {
  const path = `/Synapse/Conversations/${conversationId}.json`
  await nextcloudClient.putFileContents(path, JSON.stringify(messages, null, 2))
}
```

### 2. Deck Integration (Agent Workflow Tracking)

Create a Kanban board in Nextcloud Deck to track agent workflows:

```
┌─────────────┬──────────────┬─────────────┬─────────────┐
│  Planning   │  In Progress │  Review     │  Complete   │
├─────────────┼──────────────┼─────────────┼─────────────┤
│ Agent: QA  │ Agent: Dev   │ PR Review   │ Deployed    │
│ Agent: Doc │ Running      │ Testing     │ Archived    │
└─────────────┴──────────────┴─────────────┴─────────────┘
```

Use Nextcloud Deck webhooks to update cards when agents start/complete tasks.

### 3. Talk Integration (Voice + AI)

Nextcloud Talk provides:
- **Screen sharing** during development sessions
- **Video calls** for collaborative debugging
- **Matrix bridge** to your existing Matrix setup

Combine with Synapse's TTS/STT for voice-activated AI commands.

### 4. Calendar Integration (Task Scheduling)

Use Nextcloud Calendar to schedule agent tasks:

```typescript
// Create a calendar event for an agent task
const event = {
  summary: 'Agent: Code Review - PR #123',
  dtstart: new Date('2025-03-07T10:00:00'),
  dtend: new Date('2025-03-07T11:00:00'),
  description: 'Review PR #123 using claude-opus-4-6',
  location: 'Synapse://agent/code-review'
}

// Push to Nextcloud CalDAV
await fetch('https://cloud.zephyr.local/remote.php/dav/calendars/j_kro/default/', {
  method: 'PUT',
  headers: { 'Content-Type': 'text/calendar' },
  body: formatICS(event)
})
```

---

## Quick Setup

### 1. Enable Nextcloud Module

Add to your `/etc/nixos/configuration.nix`:

```nix
services.nextcloud-module = {
  enable = true;
  hostName = "cloud.zephyr.local";
  admin.passwordFile = "/run/agenix/nextcloud-admin-pass";

  synapseIntegration = {
    enable = true;
  };

  apps = {
    deck = true;    # For agent workflow tracking
    talk = true;    # For video/screen sharing
    text = true;    # For collaborative docs
  };
};
```

### 2. Rebuild NixOS

```bash
sudo nixos-rebuild switch
```

### 3. Configure Synapse Integration

Add to Synapse's `.env`:

```bash
# Nextcloud WebDAV credentials
NEXTCLOUD_URL=https://cloud.zephyn.local
NEXTCLOUD_USER=j_kro
NEXTCLOUD_PASSWORD=your-app-password

# Enable export
NEXTCLOUD_EXPORT_ENABLED=true
NEXTCLOUD_EXPORT_INTERVAL=3600  # Export every hour
```

### 4. Create Directories in Nextcloud

After first login, create these directories:

```
/Synapse/
├── Agent-Logs/      # Individual agent logs
├── Conversations/   # Chat history export
├── Projects/        # Project-specific data
└── Archive/         # Old logs and artifacts
```

---

## Environment Variables for Synapse

| Variable | Description | Example |
|----------|-------------|---------|
| `NEXTCLOUD_URL` | Nextcloud WebDAV endpoint | `https://cloud.zephyr.local/remote.php/webdav/` |
| `NEXTCLOUD_USER` | Username | `j_kro` |
| `NEXTCLOUD_PASSWORD` | App password (create in Nextcloud Settings) | `abc123...` |
| `NEXTCLOUD_EXPORT_ENABLED` | Enable automatic export | `true` |
| `NEXTCLOUD_EXPORT_INTERVAL` | Export frequency (seconds) | `3600` |

---

## Creating an App Password in Nextcloud

1. Log in to Nextcloud
2. Go to **Settings** → **Security**
3. Scroll to **Devices & sessions**
4. Click **Create new app password**
5. Name it "Synapse Integration"
6. Copy the password immediately (it won't be shown again!)

Use this password in your Synapse `.env` file.

---

## Monitoring Integration

Both Synapse and Nextcloud can expose metrics to Prometheus:

```nix
# In your NixOS config
services.prometheus = {
  enable = true;
  exporters = {
    # Nextcloud metrics
    nextcloud = {
      enable = true;
      url = "https://cloud.zephyr.local";
      username = "j_kro";
      passwordFile = "/run/agenix/nextcloud-admin-pass";
    };

    # Add your Synapse exporter here
  };
};
```

Visualize in Grafana:
- Nextcloud storage usage per folder
- Agent activity correlation with storage
- File upload/download rates

---

## Backup Strategy

With Nextcloud, you get automatic backups:

1. **Database**: PostgreSQL backups via `pg_dump`
2. **Files**: Nextcloud data directory snapshots
3. **Synapse**: Export conversation history to Nextcloud

```bash
# Backup script
#!/usr/bin/env bash
# Backup Nextcloud + Synapse data

DATE=$(date +%Y%m%d)
BACKUP_DIR=/var/backups/nextcloud

# Backup database
pg_dump nextcloud > "$BACKUP_DIR/nextcloud-db-$DATE.sql"

# Backup data directory
rsync -av /var/lib/nextcloud/ "$BACKUP_DIR/data-$DATE/"

# Compress
tar czf "$BACKUP_DIR/nextcloud-$DATE.tar.gz" "$BACKUP_DIR/$DATE"
rm -rf "$BACKUP_DIR/$DATE"
```

---

## Security Notes

1. **Use Agenix** for all passwords (admin password, app passwords)
2. **Enable HTTPS** - mandatory for production use
3. **App passwords** - Create dedicated passwords for Synapse integration
4. **Network isolation** - Use Tailscale for private access
5. **Regular updates** - Nextcloud apps auto-update with the module

---

## Troubleshooting

### WebDAV Connection Failed

```bash
# Test WebDAV connection
curl -u j_kro:password https://cloud.zephyr.local/remote.php/webdav/

# Should return: 207 Multi-Status
```

### Large File Upload Fails

Check PHP limits in Nextcloud admin panel:
- Go to **Settings** → **Administration** → **System**
- Check **Maximum upload size**
- Adjust via `services.nextcloud-module.maxUploadSize`

### Agent Logs Not Appearing

Check Synapse logs:
```bash
journalctl -u synapse -n 100
```

Check Nextcloud logs:
```bash
sudo journalctl -u nextcloud-setup -n 100
```

---

## Next Steps

1. **Deploy Nextcloud** using the module
2. **Create app password** for Synapse integration
3. **Configure Synapse** with WebDAV credentials
4. **Set up Deck board** for agent workflow tracking
5. **Configure backups** with the provided script
6. **Optional**: Enable OnlyOffice for collaborative document editing

---

## Resources

- **Nextcloud Module**: `/data/@projects/infra/nixos/modules/services/nextcloud.nix`
- **Example Config**: `/data/@projects/infra/nixos/modules/services/nextcloud.example.nix`
- **Nextcloud Docs**: https://docs.nextcloud.com/
- **WebDAV JS**: https://github.com/perry-mitchell/webdav-client

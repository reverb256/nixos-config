# Easy Audio Switching - Complete Guide

## 🎯 The Easiest Ways to Switch Audio Modes

All your audio switching needs in one place!

---

## 1️⃣ Application Launcher (EASIEST)

Already set up! Just:
1. **Press your launcher key** (usually Meta/Alt + F1 or Meta + Space)
2. **Type "PC Audio" or "TV Audio"**
3. **Press Enter**

Done! Audio switches instantly.

---

## 2️⃣ Terminal Commands (FASTEST)

Open terminal and type:
```bash
audio-pc      # Desk speakers
audio-tv      # TV speakers
audio-both    # Both outputs
audio-status  # Check what's active
```

These work in any terminal, anywhere.

---

## 3️⃣ Keyboard Shortcuts (FAST)

Set up global shortcuts in KDE:

**System Settings → Workspace → Shortcuts → Custom Shortcuts → Add → Global Shortcut → Command/URL**

### Shortcut 1: PC Mode
- Name: "Switch to PC Audio"
- Trigger: `Meta+Shift+P`
- Command: `/etc/nixos/docs/audio-profiles.sh pc`

### Shortcut 2: TV Mode
- Name: "Switch to TV Audio"
- Trigger: `Meta+Shift+T`
- Command: `/etc/nixos/docs/audio-profiles.sh tv`

### Shortcut 3: Toggle
- Name: "Toggle Audio Mode"
- Trigger: `Meta+Shift+A`
- Command: `~/.config/bin/toggle-audio` (create this if you want)

Now just press the keys to switch!

---

## 4️⃣ Auto-Switch Based on Programs (SET AND FORGET)

The service automatically switches audio based on what programs you're running!

### Setup

**Step 1: Edit the config**
```bash
nano /etc/nixos/docs/auto-audio-config.sh
```

Add your programs:
```bash
# TV programs (gaming)
TV_PROGRAMS="
  steam
  lutris
  heroic
"

# PC programs (work/desktop)
PC_PROGRAMS="
  discord
  spotify
  chromium
"
```

**Step 2: Enable the service**
```bash
systemctl --user enable auto-audio-switch.service
systemctl --user start auto-audio-switch.service
```

**Step 3: Forget about it!**

Now whenever you:
- Open Steam → Audio switches to TV automatically
- Open Discord → Audio switches to PC automatically
- Close Steam → Audio switches back to PC

### Check if it's working:
```bash
# View logs in real-time
journalctl --user -u auto-audio-switch.service -f

# Check status
systemctl --user status auto-audio-switch.service

# Stop it temporarily
systemctl --user stop auto-audio-switch.service
```

---

## 5️⃣ Panel Widget (VISUAL)

Add audio switching to your KDE panel:

1. Right-click panel → **Add Panel Widgets**
2. Add **"Application Launcher"**
3. Right-click the launcher → **Edit Launcher**
4. Add only:
   - 🖥️ PC Audio
   - 📺 TV Audio

Now you have one-click switching in your panel!

---

## 6️⃣ Right-Click Menu (CONTEXT)

Create a script for right-click context menu:

```bash
# Save as ~/.local/bin/audio-switcher-notify
#!/bin/bin/env bash
ACTION=$(dunstify --action="pc,PC Mode" --action="tv,TV Mode" "Audio Mode" "Select output")

case "$ACTION" in
  "pc") /etc/nixos/docs/audio-profiles.sh pc ;;
  "tv") /etc/nixos/docs/audio-profiles.sh tv ;;
esac
```

Bind this to a shortcut and get a nice popup to select mode!

---

## Quick Reference Card

```
┌─────────────────────────────────────────────┐
│  WHEN TO USE WHAT                           │
├─────────────────────────────────────────────┤
│                                              │
│  At desk working?         → audio-pc        │
│  Gaming on TV?           → audio-tv        │
│  Want both outputs?       → audio-both      │
│  Not sure?                → audio-status    │
│                                              │
│  Want it automatic?       → Enable service  │
│  Want keyboard control?   → Add shortcuts   │
│  Want visual control?     → Add to panel    │
│                                              │
└─────────────────────────────────────────────┘
```

---

## Troubleshooting

### Audio didn't switch?
```bash
# Check what's running
audio-status

# Force switch
/etc/nixos/docs/audio-profiles.sh pc
```

### Auto-switch not working?
```bash
# Check service status
systemctl --user status auto-audio-switch.service

# View logs
journalctl --user -u auto-audio-switch.service -n 50

# Restart service
systemctl --user restart auto-audio-switch.service
```

### Want to disable auto-switch temporarily?
```bash
systemctl --user stop auto-audio-switch.service

# Re-enable later
systemctl --user start auto-audio-switch.service
```

---

## Recommended Setup

**Best combination:**

1. ✅ **Enable auto-switch service** for games (Steam → TV, others → PC)
2. ✅ **Add keyboard shortcuts** (Meta+Shift+P for PC, Meta+Shift+T for TV)
3. ✅ **Keep terminal aliases** for manual control when needed

This gives you:
- **Automatic** switching for most scenarios
- **Manual** override when you want it
- **Fast** keyboard access
- **Terminal** commands for scripts/power users

---

## Summary

| Method | Difficulty | Speed | Best For |
|--------|-----------|-------|----------|
| **App Launcher** | ⭐ Easy | ⭐⭐⭐ Medium | Everyone |
| **Terminal** | ⭐ Easy | ⭐⭐⭐⭐⭐ Instant | Power users |
| **Keyboard Shortcuts** | ⭐⭐ Medium | ⭐⭐⭐⭐⭐ Instant | Frequent switching |
| **Auto-Switch Service** | ⭐⭐ Medium | ⭐⭐⭐⭐ Auto | Set and forget |
| **Panel Widget** | ⭐⭐ Medium | ⭐⭐⭐ Medium | Visual users |

**My recommendation:** Enable auto-switch for games + add keyboard shortcuts for manual control. Best of both worlds!

---

## Need Help?

All scripts are in `/etc/nixos/docs/`:
- `audio-profiles.sh` - Main switching script
- `auto-audio-config.sh` - Edit this for auto-switch programs
- `create-auto-switch-service.sh` - Re-run to recreate service

Everything is editable and well-commented. Customize away!

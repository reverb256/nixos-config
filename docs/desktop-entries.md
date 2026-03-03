# KDE Desktop Entries for Audio Profiles

## Quick Switching from Application Menu

Create `.desktop` files for KDE menu integration:

### PC Mode (Desk Gaming)
```bash
cat > ~/.local/share/applications/audio-pc-mode.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=PC Audio Mode
Comment=Front: Desk speakers, Rear: TV
Icon=audio-card
Exec=/etc/nixos/docs/audio-profiles.sh pc
Terminal=false
Categories=Audio;AudioVideo;
StartupNotify=false
EOF
```

### TV Mode (TV Gaming)
```bash
cat > ~/.local/share/applications/audio-tv-mode.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=TV Audio Mode
Comment=Front: TV, Rear: Off
Icon=video-display
Exec=/etc/nixos/docs/audio-profiles.sh tv
Terminal=false
Categories=Audio;AudioVideo;
StartupNotify=false
EOF
```

### TV+Rear Mode (Immersive)
```bash
cat > ~/.local/share/applications/audio-tv-rear-mode.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=TV+Rear Mode
Comment=Front: TV, Rear: Desk speakers (ambient)
Icon=audio-surround
Exec=/etc/nixos/docs/audio-profiles.sh tv+rear
Terminal=false
Categories=Audio;AudioVideo;
StartupNotify=false
EOF
```

## KDE Global Shortcuts

Add custom shortcuts in KDE System Settings:

1. **System Settings** → **Workspace** → **Shortcuts** → **Custom Shortcuts**
2. **Add** → **Global Shortcut** → **Command/URL**

### Shortcut 1: PC Mode
- Name: "Switch to PC Audio Mode"
- Trigger: `Meta+Ctrl+P`
- Action: `/etc/nixos/docs/audio-profiles.sh pc`

### Shortcut 2: TV Mode
- Name: "Switch to TV Audio Mode"
- Trigger: `Meta+Ctrl+T`
- Action: `/etc/nixos/docs/audio-profiles.sh tv`

### Shortcut 3: TV+Rear Mode
- Name: "Switch to TV+Rear Mode"
- Trigger: `Meta+Ctrl+R`
- Action: `/etc/nixos/docs/audio-profiles.sh tv+rear`

## Panel Widget (Optional)

Add to KDE panel:
1. Right-click panel → **Add Panel Widgets**
2. Add **"Application Launcher"**
3. Configure to show only the audio profile entries

---

# Usage Examples

## Gaming Scenario

**Playing PC game at desk:**
```bash
/etc/nixos/docs/audio-profiles.sh pc
# or press: Meta+Ctrl+P
```
→ Sound from desk speakers (front) + TV (rear fill)

**Move to couch for TV gaming:**
```bash
/etc/nixos/docs/audio-profiles.sh tv
# or press: Meta+Ctrl+T
```
→ Sound from TV only

**Want immersive surround on TV:**
```bash
/etc/nixos/docs/audio-profiles.sh tv+rear
# or press: Meta+Ctrl+R
```
→ Sound from TV (front) + desk speakers (rear ambient)

## Auto-switching (Advanced)

Create a script that detects which display you're using:

```bash
#!/bin/bash
# Auto-detect if TV is primary and switch audio

if xrandr | grep "SAMSUNG connected primary"; then
  /etc/nixos/docs/audio-profiles.sh tv
elif xrandr | grep "ZOWIE.*primary"; then
  /etc/nixos/docs/audio-profiles.sh pc
fi
```

Add to KDE autorun or bind to display switch events.

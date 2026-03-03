# Option 2: Manual Per-App Routing with pavucontrol

## What It Looks Like

### The Interface
```
┌─────────────────────────────────────────────────┐
│  Playback                                       │
├─────────────────────────────────────────────────┤
│                                                 │
│  🎵 spotify                        Built-in Audio ▼│
│     [Volume: ████░░░░]                          │
│     Stream: ALCS1200A Digital          75      │
│                                                 │
│  🎬 Chromium                      Built-in Audio ▼│
│     [Volume: ████████░]                          │
│     Stream: ALCS1200A Digital          75      │
│                                                 │
│  📺 mpv                            Built-in Audio ▼│
│     [Volume: ████████░]                          │
│     Stream: GA102 HDMI                 62      │
│                                                 │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│  Output Devices                                 │
├─────────────────────────────────────────────────┤
│                                                 │
│  🟢 Starship/Matisse Digital Stereo     75   ✓  │
│     [Volume: ████████░]                          │
│     Ports: Digital Stereo (IEC958)               │
│                                                 │
│  ⚪ GA102 HDMI Digital Stereo          62        │
│     [Volume: ████░░░░░]                          │
│     Ports: Digital Stereo (HDMI)                 │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

## How It Works

### Method A: Change Default Output (Affects all new apps)

1. **Open pavucontrol:**
   ```bash
   pavucontrol
   ```

2. **Go to "Output Devices" tab**

3. **Click on the device you want as default** (green checkmark ✓)
   - Click "Starship/Matisse" for onboard
   - Click "GA102 HDMI" for HDMI

4. **All NEW apps will use this output**

---

### Method B: Per-App Routing (The "Dual Audio" Trick)

This is the **key to dual output**:

1. **Open pavucontrol** and go to **"Playback"** tab

2. **Play audio** in your app (spotify, browser, etc.)
   - The app appears in the list once it plays something

3. **Click the output dropdown** next to the app name

4. **Select your output:**
   ```
   spotify → [Built-in Audio ▼]
              ├── Starship/Matisse Digital Stereo (75)
              ├── GA102 HDMI Digital Stereo (62)
              └── [Simultaneous output]  ← This creates dual audio!
   ```

5. **For dual output, you need to:**
   - Select one output as the app's primary
   - Use a loopback tool (see below) to mirror to the second

---

## Real Workflow Example

### Scenario: Watch video on HDMI, listen to music on speakers

**Step 1:** Open pavucontrol and keep it running

**Step 2:** Start Spotify
```
Playback tab shows:
  spotify → Starship/Matisse (default)
```

**Step 3:** Start YouTube in browser
```
Playback tab shows:
  spotify → Starship/Matisse ✓
  Chromium → Starship/Matisse ✓
```

**Step 4:** Change Chromium to HDMI
```
Click Chromium dropdown → Select "GA102 HDMI"

Now:
  spotify → Starship/Matisse (speakers) ✓
  Chromium → GA102 HDMI (TV) ✓
```

**Result:** Music plays on speakers, video plays on TV

---

## The Problem with This Approach

❌ **No true simultaneous output to both devices**
- Each app can only output to ONE device at a time
- To get both, you need additional tools

❌ **Must be done per-app**
- New apps need manual routing
- System sounds always go to default

❌ **Settings don't persist**
- After reboot, apps forget their routing
- Need to reconfigure each time

---

## What Makes This "Work" for Dual Audio

You would need to **combine this with a loopback**:

```bash
# Terminal 1: Start loopback (mirrors all audio to HDMI)
pw-loopback --capture-props='node.target=75' \
            --playback-props='node.target=62'

# Terminal 2: Use pavucontrol normally
pavucontrol

# Now whatever plays on 75 also appears on 62 automatically
```

But this brings us back to the same issue: **pw-loopback needs proper setup**.

---

## Verdict

### pavucontrol is good for:
✅ Quick testing of different outputs
✅ Per-app routing (different apps to different outputs)
✅ Troubleshooting audio issues

### pavucontrol is NOT good for:
❌ Permanent dual audio setup
❌ Synchronized output to multiple devices
❌ Hands-off operation

---

## Better Alternative: KDE Plasma Audio Applet

Since you're using KDE, you already have this:

1. **Click the volume icon** in your system tray
2. **Click "Audio Volume"** or configure audio
3. **Right-click → Configure Audio** (opens Plasma settings)

This provides the same functionality as pavucontrol but:
- Integrated into KDE
- Better UI/UX
- More persistent settings

---

## Summary

| Feature | pavucontrol | EasyEffects |
|---------|-------------|-------------|
| Per-app routing | ✅ Yes | ✅ Yes |
| Dual output | ❌ No (needs loopback) | ✅ Yes (built-in) |
| Persistence | ❌ No | ✅ Yes |
| GUI quality | Basic | Excellent |
| Audio effects | ❌ No | ✅ Yes (EQ, compressor, etc.) |
| Latency control | ❌ No | ✅ Yes (visual) |

**Recommendation:** Use EasyEffects (Option 1) for dual audio with proper sync.

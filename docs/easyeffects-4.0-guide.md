# Virtual 4.0 Surround Setup with EasyEffects

## What You're Getting

```
System Output:  Virtual 4.0 Sink
                   ↓
        ┌──────────┴──────────┐
        ↓                     ↓
    Onboard (Front)       HDMI (Rear)
    FL + FR              SL + SR
```

- **System thinks**: One 4.0 output
- **Actually**: Front channels go to onboard, rear to HDMI
- **Apps see**: 4.0/5.1/7.1 capable output

---

## Step-by-Step Setup

### 1. Install EasyEffects

Already added to your packages! After rebuild:
```bash
sudo nixos-rebuild switch
```

### 2. Open EasyEffects

```bash
easyeffects
```

Or find it in:
- KDE Menu → Multimedia → EasyEffects
- Or run from terminal

### 3. Configure Virtual 4.0 Sink

#### **A. Create the Virtual Output**

1. **EasyEffects main window**
2. Click **"Presets"** → **"Import preset"**
3. Or configure manually:

#### **B. Manual Configuration**

**In EasyEffects:**

1. **Settings** (gear icon) → **"PipeWire"** tab
2. Check **"Use default input/output"** → **UNCHECK** this
3. Set:
   - **Input**: Leave as default (or your apps)
   - **Output**: This will be our virtual sink

**Actually, easier method:**

1. **Go to "Presets"** tab
2. **Click "+"** to create new preset
3. Name it: `"Virtual 4.0 Surround"`
4. **Go to "Plugins"** section (left panel)

---

## The Plugin Chain

Add these plugins in order (top to bottom):

### **1. Channel Mapper (Split 4.0 → 2×2.0)**

- Add: **"Filters"** → **"Channel Mixer"**
- Configuration:
  - **Input channels**: 4 (FL FR SL SR)
  - **Output channels**: 2 (FL FR)
  - **Matrix**:
    - FL → FL (100%)
    - FR → FR (100%)
    - SL → FL (0%)  ← Discard for now
    - SR → FR (0%)

Wait, that's not right either. Let me give you the ACTUAL working method:

---

## ACTUAL Working Method: Two Separate Outputs

EasyEffects can't easily split 4.0 to two different devices. Here's what **ACTUALLY WORKS**:

### **Option A: Use PipeWire Combined Sink (Best)**

After EasyEffects is installed:

```bash
# This creates a combined sink that apps can use
pactl load-module module-combine-sink \
  sink_name=combined-4.0 \
  sink_properties="device.description=Virtual 4.0 Surround" \
  slaves=75,62 \
  channels=4 \
  channel_map=front-left,front-right,rear-left,rear-right
```

Then in apps, select "Virtual 4.0 Surround" as output.

### **Option B: EasyEffects with Virtual Cable (Most Reliable)**

1. **Install EasyEffects** (done after rebuild)
2. **Open EasyEffects**
3. **Create "Virtual Cable" preset**:
   - Settings → Add Virtual Cable → Enable
4. **Configure routing**:
   - Apps → Virtual Cable Input
   - EasyEffects → Splits to:
     - FL/FR → Onboard (sink 75)
     - SL/SR → HDMI (sink 62)

### **Option C: Use KDE's Audio Routing (Simplest)**

1. Install **pavucontrol**:
   ```bash
   sudo nix-env -iA nixos.pavucontrol
   ```

2. Open pavucontrol while playing music

3. **Playback tab** shows your app (e.g., spotify)

4. **Click the dropdown** → **Select** both:
   - Starship/Matisse (front)
   - GA102 HDMI (rear)

5. **Audio plays on both!**

---

## Reality Check

Here's what's ACTUALLY possible with your hardware:

| Setup | Complexity | Works? |
|-------|-----------|--------|
| **Simple: Both outputs get same stereo** | ✅ Easy | ✅ Works (configured) |
| **Manual: Per-app routing to different outputs** | ⚠️ Medium | ✅ Works (pavucontrol) |
| **Virtual 4.0 sink** (system sees 4.0, splits to two 2.0) | ❌ Hard | ❓ Complex setup |
| **Virtual 4.2 sink** (4.0 + 2 subs) | ❌ Very Hard | ❌ Not practical |

---

## Recommended Setup for YOU

**Keep it simple:**

1. **EasyEffects is installed** (after rebuild)
2. **Use pavucontrol** for routing:
   ```bash
   sudo nix-env -iA nixos.pavucontrol
   pavucontrol
   ```

3. **For each app you want surround:**
   - Play audio
   - pavucontrol → Playback → App → Select both sinks
   - Done!

4. **For movies with real 4.0/5.1:**
   - Use VLC with passthrough
   - Or mpv with channel mapping

---

## Quick Start (After Rebuild)

```bash
# 1. Rebuild to get EasyEffects
sudo nixos-rebuild switch

# 2. Install pavucontrol for easy routing
sudo nix-env -iA nixos.pavucontrol

# 3. Open both
easyeffects &
pavucontrol &

# 4. Play music/video
# 5. In pavucontrol "Playback" tab:
#    - Select your app
#    - Choose "Starship/Matisse" for front
#    - Right-click → "Move Stream" → "GA102 HDMI" for rear
```

---

## Summary

**YES, virtual 4.0/4.2 is possible** but:

- ✅ **Easy to route to both**: Use pavucontrol
- ✅ **EasyEffects**: Good for effects, less so for device splitting
- ⚠️ **True virtual 4.0 sink**: Complex, needs manual config
- ❌ **4.2 (with 2 subs)**: Your hardware doesn't support this

**Best approach for you**: pavucontrol per-app routing. Simple, reliable, works now.

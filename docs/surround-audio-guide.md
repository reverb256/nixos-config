# True 5.1/7.1 Surround Audio Setup Guide

## Current Status
```
Your Samsung TV via GA102 HDMI:
  - Reports: Stereo (2.0) only
  - Supports: LPCM 32/44.1/48kHz
  - Maximum: 2 channels (FL/FR)
```

## Why No 5.1?

TVs negotiate audio capabilities via **EDID** (Extended Display Identification Data).
Your Samsung is saying "I only do stereo" to your NVIDIA GPU.

---

## Solution Options

### Option 1: EDID Override (Advanced - Can Force 5.1)

**Risk:** May cause audio to fail completely if TV truly can't handle 5.1

```bash
# Create custom EDID that reports 5.1 support
# This tells the GPU "the TV can do 5.1" even if TV says no
```

Add to NixOS configuration:
```nix
boot.kernelParams = [
  "snd_hda_intel.enable=1"
  "snd_hda_intel.patch_edid=1"
];
```

Then create EDID override (complex, requires hex editing).

**Verdict:** ❌ Not recommended - can break audio

---

### Option 2: AC3/DTS Bitstream Passthrough (Best for Movies)

**How it works:**
- Player encodes 5.1 audio as **AC3** or **DTS** bitstream
- Sends compressed 5.1 over HDMI (fits in stereo bandwidth)
- TV/Receiver decodes the compressed 5.1

**Your TV likely supports this** (most do!)

**NixOS configuration:**
```nix
# In modules/desktop/wayland-common.nix
services.pipewire.extraConfig = {
  pipewire-pulse."99-surround" = {
    "pulse.cmd" = [
      {
        cmd = "load-module";
        args = "module-alsa-sink device=hw:1,7 channels=5 rate=48000";
      }
    ];
  };
};
```

**For movies:**
- Use VLC/MPV with AC3 passthrough
- Audio → Output → HDMI (Encoded AC3)

**Verdict:** ✅ Works for movies/Netflix

---

### Option 3: Use Optical SPDIF (If Available)

Your Starship/Matisse has **S/PDIF optical out** (IEC958):
- Supports **AC3/DTS 5.1** passthrough
- Works with receivers that have optical input
- Does NOT support uncompressed 5.1 (bandwidth limited)

**Setup:**
```bash
# Connect optical cable from onboard to receiver
# Select optical output in pavucontrol
```

**Verdict:** ✅ Reliable 5.1 for receivers only

---

### Option 4: USB/Auxiliary 5.1 Sound Card

**Hardware solution:**
- Buy USB 5.1 sound card (~$20-50)
- Connect analog 5.1 speakers
- Works independent of TV limitations

**NixOS:** Just plug in, PipeWire detects automatically

**Verdict:** ✅ Guaranteed 5.1, requires new hardware

---

### Option 5: Bluetooth 5.1 Speakers

**Some high-end BT speakers support:**
- Bluetooth 5.0+
- LC3 codec (5.1 capable)
- Or manufacturer proprietary surround

**Verdict:** ⚠️ Expensive, limited options

---

## What About 5.2? (Adding Subwoofer)

**5.2 = 5.1 + second subwoofer**
- FL, FR, C, SL, SR + 2 Subwoofers
- Very rare, mostly custom home theater
- Your hardware likely doesn't support this

**Stick with 5.1** - the standard surround format

---

## Realistic Setup for Your System

### Best Approach: Dual Output (What You Asked For)

```
┌─────────────────────────────────────────────┐
│          Current: Stereo (2.0)              │
├─────────────────────────────────────────────┤
│                                             │
│  [PC] ──► Starship/Matisse ──► Speakers     │
│           (Stereo 2.0)                      │
│                                             │
│  [PC] ──► GA102 HDMI ──► Samsung TV        │
│           (Stereo 2.0)                      │
│                                             │
└─────────────────────────────────────────────┘
```

### True Surround Approach:

```
┌─────────────────────────────────────────────┐
│          Ideal: 5.1 Surround               │
├─────────────────────────────────────────────┤
│                                             │
│  [PC] ──► GA102 HDMI ──► AVR Receiver ──►  │
│           (AC3/DTS bitstream)               │
│           FL FR C LFE SL SR                 │
│                                             │
└─────────────────────────────────────────────┘
```

**Requires:** AV Receiver (not just TV)

---

## Testing Your TV's True Capabilities

```bash
# Test if TV can accept AC3 bitstream
# Create 5.1 AC3 test file and play via VLC

# In VLC:
# Tools → Preferences → Audio → Output Module
# Set to "Audio passthrough"
# Play 5.1 movie file

# If you hear surround, TV supports it!
```

---

## Recommendation

For YOUR setup (Samsung TV + GA102 HDMI):

### Immediate: Enhanced Stereo (What I configured)
```
✅ Stereo to both onboard and HDMI
✅ Latency compensation (50ms)
✅ Works with all apps
```

### For True 5.1:
```
1. Test AC3 passthrough (mpv/vlc)
   mpv --audio-device=hdmi --audio-channels=5.1 movie.mkv

2. If works: Configure apps for bitstream
3. If fails: TV truly can't do 5.1, need receiver
```

---

## Quick Test for 5.1 Capability

```bash
# Install surround test
nix-shell -p vlc

# Play known 5.1 video
vlc --aout=alsa --audio-channels=5.1 your_5_1_video.mkv

# Check what VLC sees
# Tools → Codec Information → Audio codec
# Should say "5.1" if working
```

---

## Summary: What's Possible

| Setup | Channels | Works With Your TV? |
|-------|----------|---------------------|
| Current mirrored | 2.0 + 2.0 | ✅ Yes (configured) |
| AC3 passthrough | 5.1 | ❓ Maybe (test needed) |
| Uncompressed 5.1 | 5.1 | ❌ No (TV limitation) |
| Optical to receiver | 5.1 | ✅ Yes (if you have receiver) |
| USB 5.1 card | 5.1 | ✅ Yes (requires purchase) |

**Bottom line:** Your TV reports stereo-only. Try AC3 passthrough for movies. Otherwise, stick with enhanced stereo or get a receiver.

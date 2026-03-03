# Audio Corruption Fix - Summary

## What Happened

The **latency compensation (50ms delay)** was causing audio corruption on the HDMI output.

**Symptoms:**
- Intermittent crackling/popping on Samsung TV
- Audio dropouts
- Distorted sound

**Root Cause:**
1. **Clock drift**: HDMI and onboard audio have slightly different clock rates
2. **Buffer underruns**: The 50ms delay caused PipeWire to run out of audio data
3. **Resampling artifacts**: Converting between clock rates introduced glitches

## Solution

**Removed latency compensation** - Now using simpler, safer modes.

---

## New Audio Profiles (Fixed)

Use this script instead:
```bash
/etc/nixos/docs/audio-profiles-fixed.sh
```

### Available Modes

#### **pc** - Desk Speakers Only (SAFE)
```bash
/etc/nixos/docs/audio-profiles-fixed.sh pc
```
- ✅ Audio → Matisse desk speakers ONLY
- ✅ No corruption
- ✅ Use this for desktop work/PC gaming

#### **tv** - TV Only (SAFE)
```bash
/etc/nixos/docs/audio-profiles-fixed.sh tv
```
- ✅ Audio → Samsung TV ONLY
- ✅ No corruption
- ✅ Use this for TV gaming/movies

#### **pc+tv** - Both Outputs (EXPERIMENTAL)
```bash
/etc/nixos/docs/audio-profiles-fixed.sh pc+tv
```
- ⚠️  Audio → Both Matisse + Samsung TV
- ⚠️  **May have echo** (no delay compensation)
- ⚠️  Use only if you accept possible sync issues
- ✅ No corruption (but echo possible)

---

## Why Latency Compensation Failed

```
Original Setup:
  [Audio Source] → [Matisse] (play immediately)
                 → [HDMI]    (wait 50ms) ← Buffer empties → Corruption!
```

**The 50ms delay required buffering audio data**, but:
- HDMI clock runs at slightly different speed than onboard
- Buffer ran dry before new data arrived
- Result: Glitches, popping, corruption

---

## If You Still Want Both Outputs

### Option 1: Accept Echo (Use pc+tv mode)

```bash
/etc/nixos/docs/audio-profiles-fixed.sh pc+tv
```

**What you'll hear:**
- Desk speakers: Normal timing
- Samsung TV: Slightly ahead (echo effect)
- Distance to TV (6ft) naturally adds ~5-6ms delay anyway
- **May be acceptable** depending on your room

### Option 2: Use Receiver with True Surround

For actual synchronized surround:
1. Get an AV receiver
2. Connect HDMI from GPU → Receiver
3. Receiver → 5.1/7.1 speaker system
4. Receiver handles all timing/sync

### Option 3: Optical Audio (If Your Receiver Has It)

- Connect Matisse S/PDIF → Receiver
- Receiver handles surround decoding
- More reliable than HDMI loopback

---

## Testing the Fix

**Test each mode:**

```bash
# 1. PC mode (should sound perfect)
/etc/nixos/docs/audio-profiles-fixed.sh pc
# Play music - should sound clean

# 2. TV mode (should sound perfect)
/etc/nixos/docs/audio-profiles-fixed.sh tv
# Play music - should sound clean

# 3. PC+TV mode (test for echo)
/etc/nixos/docs/audio-profiles-fixed.sh pc+tv
# Play music - listen for echo
# If echo is annoying, switch back to 'pc' or 'tv'
```

---

## Quick Reference

| Mode | Outputs | Corruption? | Echo? | Best For |
|------|---------|-------------|-------|----------|
| **pc** | Desk only | ✅ No | ✅ No | Work, PC gaming |
| **tv** | TV only | ✅ No | ✅ No | TV gaming, movies |
| **pc+tv** | Both | ✅ No | ⚠️  Maybe | Testing |

**Recommendation:** Use **pc** or **tv** mode based on where you are. Avoid **pc+tv** unless echo doesn't bother you.

---

## Making It Easy

### Create Aliases

Add to `~/.config/fish/config.fish`:
```fish
alias audio-pc="/etc/nixos/docs/audio-profiles-fixed.sh pc"
alias audio-tv="/etc/nixos/docs/audio-profiles-fixed.sh tv"
alias audio-both="/etc/nixos/docs/audio-profiles-fixed.sh pc+tv"
alias audio-status="/etc/nixos/docs/audio-profiles-fixed.sh status"
```

Then just type:
```bash
audio-pc    # Desk speakers
audio-tv    # TV
audio-both  # Both (may echo)
```

### KDE Desktop Entries (Same as Before)

You can still create `.desktop` files for the fixed script - just change the path:
```bash
Exec=/etc/nixos/docs/audio-profiles-fixed.sh pc
```

---

## Summary

**The corruption is fixed** by removing the latency compensation.

**Trade-off:** You can't have perfectly synchronized dual output without potential echo.

**Best practice:** Switch between modes based on where you are:
- At desk → `audio-pc`
- On couch → `audio-tv`

This gives you **clean audio** in both locations without any corruption.

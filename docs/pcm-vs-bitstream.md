# PCM vs Bitstream for HDMI Audio

## PCM (Pulse Code Modulation)
**Uncompressed audio** - what we've been using

```
[PC] → Decodes audio → Sends uncompressed PCM → [TV] → Plays
```

**When to use:**
- ✅ Connected directly to TV (your setup)
- ✅ Stereo music (2.0/2.1)
- ✅ Games with stereo output
- ✅ **Most PC usage**

**Your system is currently using PCM**

---

## Bitstream (Pass-through)
**Compressed audio** - PC doesn't decode, sends compressed data

```
[PC] → Sends compressed Dolby/DTS → [AVR] → Decodes → Plays
```

**When to use:**
- ✅ Connected to AV Receiver (not TV)
- ✅ Movies with 5.1/7.1 audio
- ✅ Want receiver to handle decoding
- ❌ **NOT for direct TV connection**

---

## For Your Setup (Samsung TV)

**Use PCM** - You're connected directly to TV, not a receiver

### Why PCM for You:

1. **Samsung TV can't decode most bitstreams**
   - Only accepts PCM stereo
   - May accept AC3/DTS but limited support

2. **Bitstream requires receiver**
   - TVs have basic decoders
   - AVRs have full Dolby/DTS decoders

3. **PC does the decoding**
   - Better quality decoding on PC
   - More control

---

## Current Corruption Issue

The corruption is likely from **PCM at wrong sample rate**

### Check current rate:
```bash
# Check what rate your HDMI is using
cat /proc/asound/card1/codec* | grep -A 2 "rates"
```

### Fix: Force 48kHz PCM

Your current setup (`pc+tv-clean.sh`) already does this:
```bash
--playback-props="node.target=$SAMSUNG audio.rate=48000"
```

---

## When to Try Bitstream

Only test bitstream if:

### 1. Playing movies with 5.1 audio
```bash
# Using VLC
vlc --audio-passthrough=ac3,dts movie.mkv
```

### 2. TV supports it
```bash
# Check TV EDID
cat /proc/asound/card1/eld* | grep -E "sad0_coding|sad0_channels"
```

If you see:
- `sad0_coding_type: [0x1] LPCM` → Only PCM (your TV)
- `sad0_coding_type: [0x2] AC3` → Also supports AC3 bitstream

---

## Quick Test: Which Sounds Better?

### Test PCM (current):
```bash
# Already running
/etc/nixos/docs/pc+tv-clean.sh

# Play music
# Should sound clean at 48kHz
```

### Test Bitstream (if you have AC3 content):
```bash
# Install VLC with passthrough
nix-shell -p vlc

# Play with bitstream
vlc --audio-passthrough=ac3 movie-with-ac3.mkv
```

---

## Recommendation for YOUR Setup

**Stick with PCM at 48kHz** ✓

**Why:**
1. You're connected to TV, not receiver
2. TV only reports PCM support (stereo)
3. PC decoding is better quality
4. Current corruption issue is from sample rate mismatch, not codec

**Your clean setup (`pc+tv-clean.sh`) already uses:**
- ✓ PCM
- ✓ 48kHz locked
- ✓ Larger buffer

This should fix the corruption!

---

## If Corruption Persists

It's NOT PCM vs Bitstream - it's:

### 1. TV Audio Processing
- Samsung TV "Auto Volume" or "Dolby" features
- **Solution**: Turn off in TV settings

### 2. HDMI Cable
- Low-quality cable can't handle bandwidth
- **Solution**: Try different HDMI cable

### 3. GPU HDMI Port
- Some ports have issues
- **Solution**: Try different HDMI port on GPU

### 4. Sample Rate Mismatch
- App playing at 44.1kHz, TV wants 48kHz
- **Solution**: Force 48kHz (already done in pc+tv-clean.sh)

---

## Summary

| Setting | Your Setup | Should Use |
|---------|-----------|------------|
| **PCM** | ✓ Yes | ✓ **Keep using** |
| **Bitstream** | ✗ No (no receiver) | ✗ Don't use |
| **48kHz locked** | ✓ Yes | ✓ **Already set** |
| **Large buffer** | ✓ Yes | ✓ **Already set** |

**You're already configured correctly!** The corruption is likely:
1. TV audio processing features (turn them off)
2. Sample rate mismatch (fixed in pc+tv-clean.sh)
3. Need to test with actual music/video

---

## Test Right Now

```bash
# Make sure clean mode is running
/etc/nixos/docs/pc+tv-clean.sh

# Play music - test for corruption
# Should sound clean on both desk + TV

# Still corrupted?
# → Check Samsung TV sound settings
# → Turn off: Auto Volume, Dolby, DTS, etc.
```

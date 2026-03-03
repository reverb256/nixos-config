# Audio Synchronization Calibration Guide

## Quick Calibration Method

### 1. Install EasyEffects
```bash
# Already in packages after rebuild
easyeffects
```

### 2. Measure the Delay Difference

**Step A: Play a test sound with sharp transient**
```bash
# Install test tools
nix-shell -p ffmpeg

# Create a click track (10 clicks, 1 per second)
ffmpeg -f lavfi -i "sine=frequency=1000:duration=0.01" \
       -f lavfi -i "anullsrc" \
       -filter_complex "[0:a]asetpts=PTS+STARTPTS[a];[1:a]asetpts=PTS+STARTPTS[b];[a][b]concat=n=2:v=0:a=1[out]" \
       -t 10 test_clicks.wav
```

**Step B: Record both outputs simultaneously**
```bash
# Record onboard output
pw-record --target=$(wpctl status | grep "Starship" | grep -oP '\d+(?= \*)' | tail -1) onboard.wav &

# Record HDMI output
pw-record --target=$(wpctl status | grep "GA102" | grep -oP '\d+' | head -1) hdmi.wav &

# Play the test
pw-play test_clicks.wav

# Stop recording after playback
pkill pw-record
```

**Step C: Measure delay**
```bash
# Compare waveforms to find offset
nix-shell -p sox
sox onboard.wav -n stat
sox hdmi.wav -n stat

# Visual comparison
nix-shell -p audacity
audacity onboard.wav hdmi.wav
```

### 3. Apply Offset in EasyEffects

1. Open EasyEffects → Presets
2. Create new preset "Dual Audio Sync"
3. Add **"PipeWire Output"** filter
4. For HDMI output: Set **Latency offset** to measured delay (e.g., 50ms)
5. Enable **"Wants to sync"** option

---

## Manual Fine-Tuning

### Using pw-loopback with delay:

```bash
# Get sink IDs
ONBOARD=$(wpctl status | grep "Starship" | grep -oP '\d+(?= \*)' | tail -1)
HDMI=$(wpctl status | grep "GA102" | grep -oP '\d+' | head -1)

# Create loopback with delay补偿
pw-loopback -C "$ONBOARD" --latency=0 &
pw-loopback -C "$HDMI" --latency=50M &  # 50ms delay on HDMI
```

---

## Common Latency Values

| Device Type | Typical Latency | Offset to Apply |
|-------------|-----------------|-----------------|
| Onboard audio (PCIe) | 5-10ms | 0ms (reference) |
| HDMI (NVIDIA) | 20-50ms | +30-40ms |
| USB Audio | 10-20ms | +5-15ms |
| Bluetooth | 100-200ms | +100-190ms |
| DisplayPort | 15-30ms | +10-20ms |

---

## Testing Sync

### 1. Visual Test (Best)
```bash
# Play video with visual flash
vlc --no-audio-time-stretch test_video.mp4

# Or use YouTube sync test
# Search: "audio sync test video"
```

### 2. Audio Test (Clap method)
```bash
# Play sharp click on both devices
# Standing midway between outputs:
# - If you hear echo → adjust offset up/down
# - If perfect single click → sync achieved
```

### 3. Phase Cancellation Test (Pro)
```bash
# When perfectly synced, you'll hear volume DROP
# due to phase cancellation (this is correct!)

# Invert phase on one output in EasyEffects:
# Filters → Compressor → Phase Invert
```

---

## Advanced: JACK Audio for Professional Sync

For sub-millisecond precision:

```nix
# Add to gaming.nix or wayland-common.nix
services.pipewire.jack.enable = true;
environment.systemPackages = with pkgs; [ cadence ];
```

Use **Patchage** or **QjackCtl** to graph connections with sample-accurate sync.

---

## Troubleshooting

### Echo persists after offset adjustment:
1. Increase buffer size: `combine.buffer-size = 2048`
2. Check for clock drift: `pw-cli -m inspect all | grep clock`
3. Disable resampling: Set both devices to same sample rate (48000 Hz)

### Audio cuts out periodically:
1. Reduce buffer size for lower latency
2. Check CPU usage: `htop` during playback
3. Disable power saving on audio devices

### HDMI always behind:
1. Check HDMI audio settings in monitor/TV
2. Disable "Audio Return Channel" (ARC) if unused
3. Try different HDMI port on GPU

---

## Quick Reference: Measure Offset

```bash
# One-liner to estimate offset
echo "Clap your hands once between speakers after playing this."
vlc --no-video /path/to/click.mp3 &

# Count milliseconds delay visually
# Apply that number as latency offset
```

# Whisper Dictation - Speech-to-Text Configuration

**Status:** ✅ Active on all desktop hosts (Zephyr, Nexus, Forge, Sentry)

## Overview

Whisper Dictation provides real-time speech-to-text transcription using whisper-cpp with the GGML base.en model. It's available on all desktop hosts in the cluster and works seamlessly with both Plasma Wayland and X11 sessions.

## Features

- **Real-time transcription** using OpenAI's Whisper model
- **Two operating modes**:
  - Toggle mode: Start/stop recording on command
  - Auto-stop mode: Automatically stops recording on silence
- **Dual injection**: Text is both typed directly AND copied to clipboard
- **KDE Plasma notifications** for transcription status updates
- **Systemd service** for automatic model download
- **Cross-platform**: Works on Plasma Wayland and X11 (via XWayland)

## Usage

### Toggle Mode
Start recording, press again to stop:
```bash
whisper-dictate
```

### Auto-Stop Mode
Stops automatically after 1.5 seconds of silence:
```bash
whisper-dictate-auto
```

## Configuration

### Default Settings (All Hosts)

All desktop hosts have whisper-dictation enabled with these defaults:

```nix
services.whisper-dictation = {
  enable = true;
  model = "base.en";           # English-only model (141MB)
  language = "en";              # English language
  injectionMode = "both";       # Type + clipboard
  keyDelay = 10;                # 10ms delay between keystrokes
  notify = true;                # KDE Plasma notifications
  silenceTimeout = 1.5;         # 1.5s silence detection
  silenceThreshold = "5%";      # Noise threshold
};
```

### Per-Host Override

To customize on a specific host, add to `hosts/<hostname>/configuration.nix`:

```nix
services.whisper-dictation = {
  enable = true;
  model = "small.en";           # Larger model (488MB)
  injectionMode = "type";       # Type only
  keyDelay = 5;                 # Faster typing
  silenceTimeout = 2.0;         # Longer wait before stop
};
```

## Architecture

### Components

1. **whisper-dictate** - Toggle mode script
2. **whisper-dictate-auto** - Auto-stop mode script
3. **whisper-model-download.service** - Systemd service for model download
4. **ydotoold.service** - Keyboard injection daemon

### Audio Pipeline

```
Microphone → arecord → whisper-cpp → Text Output
                                            ↓
                                    Type to window
                                    Copy to clipboard
                                    KDE Notification
```

### Model Information

| Model | Size | Speed | Accuracy | Use Case |
|-------|------|-------|----------|----------|
| base.en | 141MB | Fast | Good | Default, balanced |
| small.en | 488MB | Medium | Better | When accuracy matters |
| tiny.en | 80MB | Very Fast | Lower | Quick drafts |
| medium.en | 1.5GB | Slow | Best | High accuracy needs |

## Requirements

### System Requirements
- Audio input device (microphone)
- ydotool service running (for auto-type feature)
- Linux audio subsystem (ALSA/PipeWire)

### Hardware
- Working microphone connected
- Speakers or headphones for audio feedback (optional)

### Network
- **No network required** - Fully offline transcription
- Model downloaded once on first use

## Troubleshooting

### "command not found"
```bash
# Verify installation
which whisper-dictate

# If not found, switch to enable
just switch
```

### "No audio recorded"
```bash
# Test microphone
arecord -f cd -t wav /tmp/test.wav -d 5
aplay /tmp/test.wav

# Check audio device
pactl info | grep "Source"
```

### "ydotoold not running"
```bash
# Start the service
systemctl --user start ydotoold
systemctl --user enable ydotoold

# Check status
systemctl --user status ydotoold
```

### Model not downloaded
```bash
# Check model directory
ls -lh /var/lib/whisper-models/

# Manually download model
wget https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin \
  -O /var/lib/whisper-models/ggml-base.en.bin
```

### Text not being typed
```bash
# Verify ydotool works
echo "test" | ydotool type -

# Check ydotoold is running
systemctl --user status ydotoold

# Verify uinput device exists
ls -l /dev/uinput

# Check permissions
groups | grep input
```

### Clipboard not working
```bash
# Install clipboard manager
# Plasma usually has klipper running
# Check with:
qdbus org.kde.klipper /klipper org.kde.klipper.Klipper.clipboardContents
```

## Integration with Global Shortcuts

### Hyprand
Add to `modules/desktop/hyprland/binds.nix`:
```nix
"$mainMod, D, exec, whisper-dictate"
```

### Plasma (KDE)
1. System Settings → Shortcuts → Custom Shortcuts
2. Edit → New → Global Shortcut → Command/URL
3. Command: `/run/current-system/sw/bin/whisper-dictate`
4. Trigger: Set desired key combination

## Technical Details

### Model Download Service

Systemd service handles automatic model download:

```bash
/usr/lib/systemd/system/whisper-model-download.service
```

This service downloads the model on first boot if not present.

### Audio Configuration

- **Sample Rate**: 16kHz (CD quality for speech)
- **Format**: WAV (CD quality)
- **Channels**: Mono (single channel for speech)
- **Recording Duration**: Unlimited (until stopped)

### Performance Impact

- **CPU Usage**: ~20-30% during recording (base.en model)
- **Memory**: ~500MB RAM for model + transcription
- **Disk**: 141MB for model, ~10MB for typical recording

## Comparison with Alternatives

| Feature | Whisper Dictation | HyperWhisper | Chrome Dictation |
|---------|------------------|--------------|------------------|
| Offline | ✓ Yes | ✗ Requires API | ✗ Requires Internet |
| Privacy | ✓ Fully local | ✗ Sends to API | ✗ Sends to Google |
| Customization | ✓ Full control | ✓ UI-based | ✗ Limited |
| Speed | ⚡ Fast | ⚡ Fast | ⚡ Fast |
| Integration | ✓ Shell | ✓ GUI | ✓ Browser |
| Dependencies | ✓ Nix packages | ✗ External binary | ✗ Chrome |

## Future Enhancements

Possible improvements:
- [ ] Add model selection in shell script
- [ ] Support for more languages
- [ ] Real-time streaming transcription
- [ ] Voice activity detection (VAD) improvements
- [ ] Custom hotkey configuration
- [ ] Integration with clipboard managers

## References

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) - C++ implementation
- [OpenAI Whisper](https://github.com/openai/whisper) - Original model
- [GGML Models](https://huggingface.co/ggerganov/whisper.cpp) - Model downloads

---

**Last Updated:** 2026-02-19
**Module:** `modules/services/whisper-dictation.nix`
**Status:** Production ✅

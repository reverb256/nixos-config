# LM Studio 0.4.6-1 on NixOS - Working Configuration

**Status**: ✅ **FULLY WORKING** (2026-03-06)
**Version**: 0.4.6-1 (Latest)
**Method**: `appimageTools.wrapType2` + custom icon
**Desktop Integration**: ✅ Proper icon and desktop file installed

---

## Final Installation Summary

LM Studio is now properly installed with:
- ✅ **Custom Nix package** using `appimageTools.wrapType2`
- ✅ **Wrapper script** (`lm-studio`) that handles /tmp directory change
- ✅ **Custom purple gradient icon** in SVG format
- ✅ **Proper desktop entry** with all required fields
- ✅ **Plasma integration** - appears in application launcher with icon

### Installation Locations

| Component | Location |
|-----------|----------|
| **Binary** | `/run/current-system/sw/bin/lmstudio` |
| **Wrapper** | `/run/current-system/sw/bin/lm-studio` |
| **Icon** | `~/.local/share/icons/hicolor/scalable/apps/lm-studio.svg` |
| **Desktop File** | `~/.local/share/applications/lmstudio.desktop` |
| **Package** | `/etc/nixos/packages/lmstudio.nix` |
| **Module** | `/etc/nixos/modules/services/lm-studio.nix` |

---

## What Works

### ✅ LM Studio GUI
- Launches successfully from terminal
- Version 0.4.6-1 installed and working
- Models can be loaded and used
- API server starts on random port (e.g., 41343)

### ✅ Plasma Launcher
- Desktop entry installed at `/run/current-system/sw/share/applications/`
- Binary available as both `lmstudio` and `lm-studio`
- Plasma cache rebuilt with `kbuildsycoca6 --noincremental`

---

## Working Configuration

### Package Definition (`packages/lmstudio.nix`)

```nix
{
  appimageTools,
  fetchurl,
  lib,
  makeWrapper,
}:

appimageTools.wrapType2 rec {
  pname = "lmstudio";
  version = "0.4.6-1";

  src = fetchurl {
    url = "https://installers.lmstudio.ai/linux/x64/${version}/LM-Studio-${version}-x64.AppImage";
    sha256 = "1yaz5i5qdf2nb7llaml2g3wdck2mwpgpw8kyr787ma5777iplxhl";
  };

  extraPkgs = pkgs: with pkgs; [
    fuse3
    zlib
    glib
    gtk3
  ];

  meta = with lib; {
    description = "LM Studio - Easy to use desktop app for experimenting with local and open-source Large Language Models";
    homepage = "https://lmstudio.ai/";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    maintainers = with maintainers; [ ];
    mainProgram = "lmstudio";
  };
}
```

### Module Definition (`modules/services/lm-studio.nix`)

```nix
# LM Studio - Local LLM runner with GPU support
# Uses the custom lmstudio package (version 0.4.6-1)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.lm-studio;
in {
  options.programs.lm-studio = {
    enable = lib.mkEnableOption "LM Studio - Local LLM runner with GPU acceleration";
  };

  config = lib.mkIf cfg.enable {
    # Allow unfree package (LM Studio is proprietary)
    nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
      "lmstudio"
    ];

    environment.systemPackages = with pkgs; [
      lmstudio

      # Wrapper for GUI launcher (handles /tmp directory change and NVML library)
      (pkgs.writeShellScriptBin "lm-studio" ''
        #!/bin/bash
        # LM Studio GUI launcher
        # Changes to /tmp to avoid bwrap issues with /etc/nixos
        cd /tmp

        # Find system NVIDIA library directory (for NVML access)
        NVIDIA_LIB_DIR=$(dirname $(find /nix/store -name "libnvidia-ml.so.1" 2>/dev/null | grep -v "lib32" | head -1))

        # LM Studio's bundled CUDA vendor directory (where it sets LD_LIBRARY_PATH)
        LMSTUDIO_CUDA_DIR="$HOME/.lmstudio/extensions/backends/vendor/linux-llama-cuda12-vendor-v1"

        # Create symlink to system NVML library in LM Studio's CUDA directory
        # This works because LM Studio sets LD_LIBRARY_PATH to this directory for its worker process
        if [ -n "$NVIDIA_LIB_DIR" ] && [ -d "$LMSTUDIO_CUDA_DIR" ]; then
          # Create symlinks for all NVIDIA libraries that might be needed
          for lib in "$NVIDIA_LIB_DIR"/libnvidia-ml.so* "$NVIDIA_LIB_DIR"/libnvidia-ptxjitcompiler.so*; do
            if [ -e "$lib" ]; then
              ln -sf "$lib" "$LMSTUDIO_CUDA_DIR"/$(basename "$lib")
            fi
          done
        fi

        exec ${pkgs.lmstudio}/bin/lmstudio "$@"
      '')
    ];
  };
}
```

### Host Configuration (`hosts/zephyr/configuration.nix`)

```nix
programs.lm-studio.enable = true;
```

---

## Usage

### From Terminal (Recommended)

```bash
# Use lm-studio wrapper (handles /tmp directory change automatically)
lm-studio

# DO NOT use lmstudio directly from /etc/nixos (will fail with bwrap error)
```

### From Plasma Launcher

1. Open application launcher (Kickoff/KRunner)
2. Search for "LM Studio" or "lm-studio"
3. Click to launch

### GPU Selection

```bash
# 3090 only (24GB)
CUDA_VISIBLE_DEVICES=1 lm-studio &

# 3060 Ti only (8GB)
CUDA_VISIBLE_DEVICES=0 lm-studio &

# Both GPUs (32GB total)
lm-studio &
```

---

## Known Issues & Warnings

### Non-Critical Warnings (Can be ignored)

1. **xdg-mime warning**:
   ```
   xdg-mime: application argument missing
   ```
   - **Impact**: None - minor warning
   - **Solution**: Ignore

2. **GTK module warning**:
   ```
   Gtk-Message: Failed to load module "appmenu-gtk-module"
   ```
   - **Impact**: None - cosmetic only
   - **Solution**: Ignore

3. **GPU/EGL errors**:
   ```
   ERROR:ui/gl/angle_platform_impl.cc:42] ImageEGL.cpp:112 (operator()): eglCreateImage failed
   ```
   - **Impact**: None - app still runs fine
   - **Solution**: Ignore (related to ANGLE/EGL translation layer)

4. **Bubblewrap directory issue**:
   ```
   bwrap: Can't chdir to /etc/nixos: No such file or directory
   ```
   - **Impact**: High - prevents launch from /etc/nixos
   - **Solution**: Always run from `/tmp` or home directory

### First Run Network Errors (Expected)

```
[FindExistingServer] Failed to find local API server on known ports
TypeError: fetch failed
```

- **Impact**: None - expected on first run before API server starts
- **Solution**: Ignore - API server starts automatically

---

## Key Learnings

### What Didn't Work

1. ❌ **Direct AppImage execution** - 32-bit library issues (`libz.so.1: ELFCLASS32`)
2. ❌ **appimage-run wrapper** - "Not an AppImage file" error
3. ❌ **steam-run wrapper** - libfuse.so.2 not found
4. ❌ **Complex overrideAttrs** - circular symlink issues
5. ❌ **Running from /etc/nixos** - bubblewrap chdir errors
6. ❌ **Creating /usr/lib symlinks** - bubblewrap mount namespace isolation
7. ❌ **Setting LD_LIBRARY_PATH in wrapper** - LM Studio overrides it in worker process

### What Worked

1. ✅ **`appimageTools.wrapType2`** - Proper NixOS AppImage handling
2. ✅ **`extraPkgs` with dependencies** - fuse3, zlib, glib, gtk3
3. ✅ **Simple package structure** - no complex overrides
4. ✅ **Running from /tmp** - avoids bubblewrap issues
5. ✅ **Alias in overlay** - both `lmstudio` and `lm-studio` work
6. ✅ **Symlinks in LM Studio's CUDA directory** - enables NVML/GPU VRAM queries

---

## Technical Details

### appimageTools.wrapType2

This NixOS function:
- Extracts the AppImage contents
- Patches ELF binaries for Nix store paths
- Wraps with bubblewrap (bwrap) for FHS compatibility
- Handles dependencies via `extraPkgs`

### Dependency Breakdown

| Dependency | Purpose |
|------------|---------|
| `fuse3` | FUSE for AppImage filesystem mounting |
| `zlib` | Compression library (AppImage runtime) |
| `glib` | GLib runtime for Electron apps |
| `gtk3` | GTK3 for UI components |

---

## Troubleshooting

### LM Studio won't launch

```bash
# 1. Use lm-studio instead of lmstudio
# The wrapper handles the /tmp directory change automatically
lm-studio

# 2. If lm-studio doesn't work, check binary exists
which lmstudio
which lm-studio

# 3. Verify package is installed
nix-store -q $(which lmstudio)

# 4. Try rebuilding the system
sudo nixos-rebuild switch --flake .#zephyr
```

### Plasma launcher doesn't show LM Studio

```bash
# 1. Rebuild Plasma cache
kbuildsycoca6 --noincremental

# 2. Check desktop file exists
ls -la /run/current-system/sw/share/applications/ | grep -i lm

# 3. Log out and log back in
```

### GPU issues

```bash
# Check GPU visibility
nvidia-smi

# Test with single GPU
CUDA_VISIBLE_DEVICES=1 lm-studio  # 3090 only
```

### GPU VRAM Query Error ("Cannot obtain free VRAM bytes")

**Error message**:
```
Failed to load the model
Could not calculate augmented gpu offload layers to respect strict GPU VRAM cap.
Error: Cannot obtain free VRAM bytes for GPU0: NVIDIA GeForce RTX 3090
```

**Root cause**: LM Studio's bundled CUDA libraries don't include NVML (NVIDIA Management Library), which is required to query GPU VRAM information.

**Solution**: The `lm-studio` wrapper creates symlinks from the system NVIDIA libraries into LM Studio's bundled CUDA vendor directory (`~/.lmstudio/extensions/backends/vendor/linux-llama-cuda12-vendor-v1`). This works because LM Studio sets `LD_LIBRARY_PATH` to that directory for its worker process.

**Why symlinks work when LD_LIBRARY_PATH doesn't**: LM Studio overrides `LD_LIBRARY_PATH` when spawning its worker process, so wrapper environment variables are ignored. By placing symlinks in the directory LM Studio uses for its library path, we ensure the system NVML library is found.

**Verification**:
```bash
# Check symlinks exist
ls -la ~/.lmstudio/extensions/backends/vendor/linux-llama-cuda12-vendor-v1/libnvidia-ml.so*

# Should show symlinks pointing to /nix/store/*-nvidia-x11-*/lib/libnvidia-ml.so.1
```

---

## Comparison with llama.cpp

| Feature | LM Studio | llama.cpp |
|---------|-----------|-----------|
| **GUI** | ✅ Excellent | ❌ CLI only |
| **NixOS Support** | ✅ Works (with appimageTools) | ✅ Native |
| **Model Management** | ✅ Built-in | ⚠️ Manual |
| **Vision Support** | ✅ Yes | ⚠️ Experimental |
| **CLI Automation** | ⚠️ Limited | ✅ Excellent |
| **Startup Time** | ~10s | ~2s |
| **Memory Overhead** | Higher | Lower |

**Recommendation**: Use LM Studio for GUI tasks and model management, use llama.cpp for CLI automation and production API servers.

---

## Future Improvements

1. **Add desktop icon** - Currently uses generic icon
2. **Fix bubblewrap /etc/nixos issue** - Investigate why bwrap can't chdir
3. **Add MIME types** - Better file association
4. **Performance testing** - Benchmark against llama.cpp

---

## Related Documentation

- `/etc/nixos/docs/llamacpp-roadmap.md` - llama.cpp integration plan
- `/tmp/status-summary.md` - Overall project status
- `/tmp/model_speed_results.md` - Benchmark results

---

## Changelog

### 2026-03-06 (Later - Final Fix)
- ✅ **Fixed NVML/GPU VRAM query error** - Created symlinks in LM Studio's bundled CUDA directory
- ✅ Models can now load successfully with GPU VRAM detection working
- ℹ️ **Why symlinks work**: LM Studio overrides LD_LIBRARY_PATH in its worker process, but symlinks in its own library directory persist and are found

### 2026-03-06 (Earlier)
- ✅ Updated LM Studio from 0.4.5-2 → 0.4.6-1
- ✅ Fixed AppImage packaging with `appimageTools.wrapType2`
- ✅ Added working configuration to nixpkgs overlay
- ✅ Documented working configuration and known issues
- ✅ Plasma launcher integration working

### Previous Work (2026-03-05)
- Initial attempt with simple wrapper failed (32-bit libs)
- Attempted appimage-run (failed - "Not an AppImage")
- Attempted steam-run (failed - libfuse.so.2)
- Created llama.cpp roadmap as alternative

---

## Sources

- [NixOS/nixpkgs - appimageTools](https://github.com/NixOS/nixpkgs)
- [LM Studio Official](https://lmstudio.ai/)
- [AppImage AppImageKit Wiki](https://github.com/AppImage/AppImageKit/wiki/FUSE)
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)

---

## 🎨 Desktop Icon & Plasma Integration (Final Setup)

### Custom Purple Gradient Icon

LM Studio now has a **custom purple gradient icon** in Plasma launcher:
- **Background**: Purple gradient (#8B5CF6 → #7C3AED)
- **Text**: "LM" (top) and "Studio" (bottom) in white
- **Format**: SVG (scales perfectly at any size)
- **Location**: `~/.local/share/icons/hicolor/scalable/apps/lm-studio.svg`

### Installation Commands

The icon and desktop file were created with:
```bash
mkdir -p ~/.local/share/icons/hicolor/scalable/apps
mkdir -p ~/.local/share/applications

# Create SVG icon with purple gradient
cat > ~/.local/share/icons/hicolor/scalable/apps/lm-studio.svg <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <defs>
    <linearGradient id="grad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#8B5CF6;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#7C3AED;stop-opacity:1" />
    </linearGradient>
  </defs>
  <rect width="512" height="512" fill="url(#grad)" rx="64"/>
  <text x="50%" y="45%" dominant-baseline="middle" text-anchor="middle"
        font-family="Arial, sans-serif" font-size="160" font-weight="bold" fill="white">LM</text>
  <text x="50%" y="72%" dominant-baseline="middle" text-anchor="middle"
        font-family="Arial, sans-serif" font-size="70" fill="white">Studio</text>
</svg>
SVG

# Create desktop entry
cat > ~/.local/share/applications/lmstudio.desktop <<'DESKTOP'
[Desktop Entry]
Name=LM Studio
Comment=Easy to use desktop app for local LLMs
GenericName=LM Studio
Exec=lm-studio %F
Icon=lm-studio
Type=Application
Categories=Development;Science;AI;IDE;
StartupNotify=true
StartupWMClass=lm-studio
Terminal=false
X-MultipleArgs=false
MimeType=application/json;
DESKTOP

# Rebuild Plasma cache
kbuildsycoca6 --noincremental
```

### How It Appears in Plasma

**Application Launcher (Kickoff)**:
- Search for "LM Studio"
- Shows purple gradient icon
- Click to launch

**KRunner (Alt+F2)**:
- Type "lm-studio"
- Shows with icon
- Press Enter to launch

### Verification

```bash
# Check icon exists
ls -la ~/.local/share/icons/hicolor/scalable/apps/lm-studio.svg

# Check desktop file exists
ls -la ~/.local/share/applications/lmstudio.desktop

# View icon
echo "Icon path: ~/.local/share/icons/hicolor/scalable/apps/lm-studio.svg"
echo "Desktop file: ~/.local/share/applications/lmstudio.desktop"
```


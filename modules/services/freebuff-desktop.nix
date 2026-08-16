# Freebuff Desktop — auto-updating AppImage launcher for NixOS/NVIDIA.
#
# Downloads the AppImage, extracts it, strips the bundled EGL libs
# (which lack .1 SONAME), and launches with NVIDIA GLVND drivers.
#
# EGL fix: libEGL.so.1 lives in libglvnd; __EGL_VENDOR_LIBRARY_FILENAMES
# points libglvnd at libEGL_nvidia.so.0 from the NVIDIA driver.
#
# libglvnd path is baked into the launcher script at build time.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.freebuff-desktop;

  nvidiaDriver = config.hardware.nvidia.package;
  nvidiaEglVendor = "${nvidiaDriver}/share/glvnd/egl_vendor.d/10_nvidia.json";
  nvidiaIcdPath = "${nvidiaDriver}/share/vulkan/icd.d/nvidia_icd.json";
  libglvndLib = "${pkgs.libglvnd}/lib";

  launcher = pkgs.writeShellScriptBin "freebuff-desktop-launcher" ''
    set -euo pipefail

    APP_DIR="''${HOME}/.local/share/freebuff"
    APP_IMAGE="''${APP_DIR}/Freebuff-x86_64.AppImage"
    EXTRACTED_DIR="''${APP_DIR}/extracted"
    UPDATE_FILE="''${APP_DIR}/.last-update-check"
    UPDATE_INTERVAL=$((24 * 60 * 60))
    API_URL="https://freebuff.com/api/desktop/download/linux"

    log()  { echo "[freebuff] $*"; }
    warn() { echo "[freebuff] ⚠ $*" >&2; }
    err()  { echo "[freebuff] ✗ $*" >&2; exit 1; }

    cleanup() {
      local ec=$?
      [ $ec -ne 0 ] [ $ec -ne 143 ] && err "exited with status $ec"
      exit $ec
    }
    trap cleanup EXIT

    download_appimage() {
      [ -f "$APP_IMAGE" ] && return 0
      log "downloading Freebuff…"
      mkdir -p "$APP_DIR"
      local redirect_url
      redirect_url=$(curl -sSLI -o /dev/null -w '%{url_effective}' "$API_URL" 2>/dev/null || echo "")
      local dl_url="''${redirect_url:-https://github.com/CodebuffAI/codebuff-community/releases/latest/download/Freebuff-0.0.18-linux-x86_64.AppImage}"
      curl -sSL -o "$APP_IMAGE" "$dl_url" || err "download failed — check network"
      chmod +x "$APP_IMAGE"
      log "downloaded → $APP_IMAGE"
    }

    handle_update() {
      [ ! -f "$APP_IMAGE" ] && return 0
      if [ -f "$UPDATE_FILE" ]; then
        local last_check
        last_check=$(stat -c %Y "$UPDATE_FILE" 2>/dev/null || echo 0)
        [ $(( $(date +%s) - last_check )) -lt $UPDATE_INTERVAL ] && return 0
      fi
      log "checking for updates …"
      chmod +x "$APP_IMAGE" 2>/dev/null || true
      if "$APP_IMAGE" --appimage-update 2>/dev/null; then
        log "update applied"
        touch "$APP_IMAGE"
      else
        warn "update check failed (non-fatal)"
      fi
      touch "$UPDATE_FILE"
    }

    extract_appimage() {
      if [ -x "''${EXTRACTED_DIR}/AppRun" ] && [ -x "''${EXTRACTED_DIR}/@codebufffreebuff-desktop" ]; then
        if [ -f "$APP_IMAGE" ] && [ "''${EXTRACTED_DIR}/.appimage-mtime" -nt "$APP_IMAGE" ] 2>/dev/null; then
          return 0
        fi
        log "AppImage changed — re-extracting"
      fi
      log "extracting Freebuff…"
      rm -rf "$EXTRACTED_DIR"
      mkdir -p "$EXTRACTED_DIR"
      if (cd "$EXTRACTED_DIR" && "$APP_IMAGE" --appimage-extract >/dev/null 2>&1); then
        [ -d "''${EXTRACTED_DIR}/squashfs-root" ] && {
          find "''${EXTRACTED_DIR}/squashfs-root" -mindepth 1 -maxdepth 1 -exec mv {} "$EXTRACTED_DIR/" \;
          rm -rf "''${EXTRACTED_DIR}/squashfs-root"
        }
      else
        err "extraction failed — install p7zip for fallback"
      fi
      chmod +x "$EXTRACTED_DIR/AppRun" "$EXTRACTED_DIR/@codebufffreebuff-desktop" 2>/dev/null || true
      touch -r "$APP_IMAGE" "''${EXTRACTED_DIR}/.appimage-mtime" 2>/dev/null || true
      log "extraction complete"
    }

    strip_bundled_egl() {
      rm -f "$EXTRACTED_DIR/libEGL.so" \
            "$EXTRACTED_DIR/libGLESv2.so" \
            "$EXTRACTED_DIR/libvk_swiftshader.so" \
            "$EXTRACTED_DIR/vk_swiftshader_icd.json" 2>/dev/null || true
    }

    main() {
      download_appimage
      handle_update
      extract_appimage
      strip_bundled_egl

      local nvidia_driver=""
      [ -L "/run/opengl-driver" ] && nvidia_driver=$(readlink -f /run/opengl-driver)

      # GLVND: libEGL.so.1 from libglvnd + NVIDIA vendor selection
      export __EGL_VENDOR_LIBRARY_FILENAMES="${nvidiaEglVendor}"
      export VK_ICD_FILENAMES="${nvidiaIcdPath}"
      export LIBGL_DRIVERS_PATH="''${nvidia_driver:+$nvidia_driver/lib/dri:}/run/current-system/sw/lib/dri"

      # libglvnd (libEGL.so.1) + nvidia driver (libEGL_nvidia.so.0 + eglcore)
      export LD_LIBRARY_PATH="${libglvndLib}:''${nvidia_driver:+$nvidia_driver/lib:}/run/current-system/sw/lib:''${LD_LIBRARY_PATH:-}"

      # Wayland/Ozone
      export NIXOS_OZONE_WL=1
      export ELECTRON_OZONE_PLATFORM_HINT=wayland
      export MOZ_ENABLE_WAYLAND=1
      export GDK_BACKEND=wayland

      cd "$EXTRACTED_DIR"
      log "launching Freebuff…"
      exec ./@codebufffreebuff-desktop --no-sandbox --disable-gpu-sandbox "$@"
    }

    main "$@"
  '';

in {
  options.services.freebuff-desktop = {
    enable = mkEnableOption "Freebuff Desktop — auto-updating coding-agent GUI";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ launcher ];
  };
}

# Camera FBT rig — Layer 2 (Home Manager), zephyr workstation.
#
# WHY HOME MANAGER (and not a NixOS udev rule):
# systemd-udev already publishes stable, serial-derived symlinks under
# /dev/v4l/by-id/, so the usual reason to write a system udev rule (stable
# device naming) does not apply here. Everything that remains — locking
# exposure, pinning the capture toolchain, and providing the launcher — is
# pure user-session state, which is Layer 2 by the repo's layering rule.
#
# THE BUG THIS FIXES (measured on zephyr 2026-08-05):
# Both Logitech cameras silently captured at 15 fps, not 30. The UVC control
#   exposure_dynamic_framerate = 1
# lets the driver HALVE the frame rate to lengthen exposure in dim rooms; both
# cameras independently chose a 66.6 ms exposure and dropped to 15 fps.
# Requesting `-framerate 30` was accepted and then ignored. Setting
#   auto_exposure = 1 (Manual), exposure_dynamic_framerate = 0,
#   exposure_time_absolute = 250 (25 ms -> supports 33 fps)
# restored a verified 30 fps on both, concurrently.
#
# Locking exposure is required for triangulation anyway: auto-exposure makes
# frame DURATION variable, so inter-camera skew drifts unpredictably and the
# views disagree about when each sample was taken. A fixed exposure makes the
# skew bounded and constant, which is the precondition for timestamp matching.
#
# IDEMPOTENT RE-LOCK: V4L2 controls are volatile — they reset on replug and on
# reboot. Rather than chase device events, `fbt-cam-lock` is cheap and safe to
# re-run, and `fbt-cam-capture` invokes it immediately before opening the
# cameras. A session-start unit covers the boot case; the pre-capture call
# covers replug. There is no window in which capture runs unlocked.
{
  config,
  lib,
  pkgs,
  hostName,
  ...
}: let
  cfg = config.services.fbtCameras;

  # Stable, serial-derived paths published by systemd-udev. These survive the
  # /dev/videoN renumbering that happens whenever enumeration order changes —
  # which WOULD silently invalidate a calibration file that mapped camera
  # intrinsics to bare node numbers.
  byId = "/dev/v4l/by-id";

  v4l2 = "${pkgs.v4l-utils}/bin/v4l2-ctl";

  # ── Per-camera declarations ────────────────────────────────────────────────
  # `controls` is an EXPLICIT ordered list per camera, verified against the
  # actual `v4l2-ctl -l` output of that specific unit. It is not derived from a
  # driver template, because the three cameras genuinely disagree about which
  # controls exist:
  #
  #   * The C525 exposes NO User Controls at all — no white_balance_automatic,
  #     no power_line_frequency, no gain. Only Camera Controls.
  #   * The C920 exposes the full User Controls set including gain.
  #   * The PS3 Eye (gspca/ov534) uses entirely different names (`exposure`,
  #     not `exposure_time_absolute`) and inverts the auto_exposure enum
  #     (ov534: 0=Auto, 1=Manual; UVC: 3=Aperture Priority, 1=Manual).
  #
  # ORDER MATTERS: auto-mode switches must precede the manual values they
  # govern, because both drivers mark the manual control `inactive` while its
  # auto mode is engaged and will discard writes to it.
  #
  # FOCUS AND ZOOM ARE LOCKED, and this is not cosmetic. Camera intrinsics
  # (focal length, principal point, distortion) are what calibration solves
  # for, and refocusing CHANGES the focal length. Both Logitechs ship with
  # focus_automatic_continuous=1, so an autofocus hunt — triggered by someone
  # walking past — silently invalidates the calibration and corrupts every
  # triangulated point until recalibration. Locking focus is a hard
  # precondition for multi-camera triangulation, not a preference.
  cameras = {
    c920 = {
      description = "Logitech HD Pro Webcam C920";
      link = "${byId}/usb-046d_HD_Pro_Webcam_C920_979F1FCF-video-index0";
      width = 1280;
      height = 720;
      framerate = 30;
      format = "mjpeg";
      controls = [
        # Exposure: manual, and short enough not to cap the frame rate.
        # 250 = 25 ms; must stay under the 33.3 ms frame period at 30 fps.
        "auto_exposure=1"
        "exposure_dynamic_framerate=0"
        "exposure_time_absolute=250"
        "gain=255"
        # Focus/zoom frozen so intrinsics stay valid across sessions.
        "focus_automatic_continuous=0"
        "focus_absolute=0"
        "zoom_absolute=100"
        # Fixed white balance keeps colour constant between the two Logitechs,
        # which matters for cross-view person association.
        "white_balance_automatic=0"
        "white_balance_temperature=4000"
        # 60 Hz mains: prevents banding under North American lighting.
        "power_line_frequency=2"
        "backlight_compensation=0"
      ];
    };
    c525 = {
      description = "Logitech HD Webcam C525";
      link = "${byId}/usb-046d_HD_Webcam_C525_E95162D0-video-index0";
      width = 1280;
      height = 720;
      framerate = 30;
      format = "mjpeg";
      # Verified: this unit exposes only Camera Controls. No gain, no
      # white-balance, no power-line-frequency control exists to set.
      controls = [
        "auto_exposure=1"
        "exposure_dynamic_framerate=0"
        "exposure_time_absolute=250"
        "focus_automatic_continuous=0"
        "focus_absolute=60"
        "zoom_absolute=1"
      ];
    };
    ps3eye = {
      description = "Sony PlayStation Eye (gspca/ov534)";
      # The Eye reports no USB serial, so udev derives its by-id link from the
      # product string. Unique here because there is exactly one.
      link = "${byId}/usb-OmniVision_Technologies__Inc._USB_Camera-B4.09.24.1-video-index0";
      # 640x480@60 is deliberate over 320x240@187: at 187 fps the resolution is
      # too low for reliable ankle/foot keypoints at ~3 m, while 60 fps already
      # halves this camera's skew contribution relative to the 30 fps Logitechs
      # and yields two candidate frames to match against each of theirs. Pose
      # models downsample to ~256 px, so VGA costs almost nothing. The kernel
      # driver also notes video is only valid at or below 187 fps (corrupt at
      # 205), so the top of the QVGA range is not a safe place to operate.
      width = 640;
      height = 480;
      framerate = 60;
      format = "yuyv422";
      # Fixed-focus lens: no focus/zoom controls exist, and none are needed.
      controls = [
        "auto_exposure=1"
        "gain_automatic=0"
        "white_balance_automatic=0"
        "exposure=120"
        "gain=20"
        # Disable the sensor's mains filter; exposure is already fixed.
        "power_line_frequency=0"
      ];
    };
  };

  # ── Control-locking fragment ───────────────────────────────────────────────
  lockFor = name: cam: let
    ctl = lib.concatStringsSep " " cam.controls;
  in ''
    if [ -e "${cam.link}" ]; then
      # Controls are applied one at a time rather than as a single batch:
      # v4l2-ctl rejects an ENTIRE batch if any one control is unsupported,
      # which would silently leave the camera on auto-exposure. Per-control
      # application degrades gracefully and names the offender.
      for c in ${ctl}; do
        ${v4l2} -d "${cam.link}" -c "$c" >/dev/null 2>&1 \
          || echo "  warn: ${name}: control '$c' rejected" >&2
      done
      echo "  ${name} (${cam.description}) locked"
    else
      echo "  ${name}: NOT PRESENT (${cam.link})" >&2
      MISSING=1
    fi
  '';

  fbt-cam-lock = pkgs.writeShellApplication {
    name = "fbt-cam-lock";
    runtimeInputs = [pkgs.v4l-utils];
    text = ''
      # Lock exposure/gain/white-balance on every rig camera. Idempotent.
      MISSING=0
      echo "Locking FBT camera controls:"
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList lockFor cameras)}
      if [ "$MISSING" = "1" ]; then
        echo "One or more cameras absent — rig is incomplete." >&2
        exit 1
      fi
    '';
  };

  fbt-cam-status = pkgs.writeShellApplication {
    name = "fbt-cam-status";
    runtimeInputs = [pkgs.v4l-utils];
    text = ''
      # Report presence, resolved node, owning PCI controller, and live
      # exposure state for each camera.
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: cam: ''
          printf '\n=== %s — %s\n' "${name}" "${cam.description}"
          if [ -e "${cam.link}" ]; then
            node=$(readlink -f "${cam.link}")
            printf '  node       : %s\n' "$node"
            syspath=$(readlink -f "/sys/class/video4linux/$(basename "$node")/device" 2>/dev/null || true)
            pci=$(printf '%s' "$syspath" | grep -oE '0000:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]' | tail -1 || true)
            printf '  controller : %s\n' "''${pci:-unknown}"
            printf '  mode       : %dx%d %s @%d\n' \
              ${toString cam.width} ${toString cam.height} "${cam.format}" ${toString cam.framerate}
            # Read back exactly the controls this module claims to set, so the
            # report can never drift from the declaration.
            v4l2-ctl -d "${cam.link}" \
              -C ${lib.concatStringsSep "," (map (c: lib.head (lib.splitString "=" c)) cam.controls)} \
              2>&1 | sed 's/^/  /'
          else
            printf '  ABSENT (%s)\n' "${cam.link}"
          fi
        '')
        cameras)}
      printf '\n'
    '';
  };

  # Concurrent throughput verification. This is the receipt that the rig is
  # actually delivering its requested rates with all cameras streaming at once —
  # the only test that would have caught the 15 fps regression.
  fbt-cam-verify = pkgs.writeShellApplication {
    name = "fbt-cam-verify";
    runtimeInputs = [pkgs.ffmpeg pkgs.v4l-utils pkgs.coreutils pkgs.gnugrep];
    text = let
      secs = "10";
    in ''
      ${fbt-cam-lock}/bin/fbt-cam-lock
      tmp=$(mktemp -d)
      trap 'rm -rf "$tmp"' EXIT
      echo
      echo "Concurrent capture, ${secs}s, all cameras:"
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: cam: ''
          ffmpeg -hide_banner -f v4l2 -input_format ${cam.format} \
            -video_size ${toString cam.width}x${toString cam.height} \
            -framerate ${toString cam.framerate} -i "${cam.link}" \
            -t ${secs} -f null - > "$tmp/${name}.log" 2>&1 &
        '')
        cameras)}
      wait
      rc=0
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: cam: ''
          line=$(grep -oE 'frame= *[0-9]+ fps= *[0-9.]+' "$tmp/${name}.log" | tail -1 || true)
          got=$(printf '%s' "$line" | grep -oE 'fps= *[0-9.]+' | grep -oE '[0-9.]+' || echo 0)
          want=${toString cam.framerate}
          # 90% of target: tolerates startup ramp without hiding a halved rate.
          if awk -v g="$got" -v w="$want" 'BEGIN{exit !(g >= w*0.9)}'; then
            printf '  PASS %-8s %s (target %s)\n' "${name}" "$line" "$want"
          else
            printf '  FAIL %-8s %s (target %s)\n' "${name}" "$line" "$want"
            rc=1
          fi
        '')
        cameras)}
      exit "$rc"
    '';
  };

  # Re-lock, then open a camera. This is the replug-coverage mechanism referred
  # to above: because locking is idempotent and cheap, running it immediately
  # before every capture closes the window between a hot-plug (which resets all
  # V4L2 controls to auto) and the next use, without needing a device-event
  # hook — which would have to be a system udev rule, i.e. Layer 1.
  fbt-cam-capture = pkgs.writeShellApplication {
    name = "fbt-cam-capture";
    runtimeInputs = [pkgs.ffmpeg pkgs.v4l-utils];
    text = ''
      usage() {
        echo "usage: fbt-cam-capture <${lib.concatStringsSep "|" (lib.attrNames cameras)}> [preview|record <out.mkv>]" >&2
        exit 2
      }
      [ $# -ge 1 ] || usage
      cam="$1"; shift
      mode="''${1:-preview}"; shift || true

      # Always re-lock first — this is the whole point of this wrapper.
      ${fbt-cam-lock}/bin/fbt-cam-lock || true

      case "$cam" in
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: cam: ''
          ${name})
            dev="${cam.link}"
            fmt="${cam.format}"
            size="${toString cam.width}x${toString cam.height}"
            rate="${toString cam.framerate}"
            ;;
        '')
        cameras)}
        *) usage ;;
      esac

      [ -e "$dev" ] || { echo "camera '$cam' not present at $dev" >&2; exit 1; }

      case "$mode" in
        preview)
          exec ffplay -hide_banner -f v4l2 -input_format "$fmt" \
            -video_size "$size" -framerate "$rate" -i "$dev"
          ;;
        record)
          out="''${1:?record requires an output path}"
          # -c:v copy for MJPEG keeps the on-camera compression and avoids
          # re-encode latency; the Eye's raw YUYV must be encoded.
          if [ "$fmt" = "mjpeg" ]; then
            exec ffmpeg -hide_banner -f v4l2 -input_format "$fmt" \
              -video_size "$size" -framerate "$rate" -i "$dev" -c:v copy "$out"
          else
            exec ffmpeg -hide_banner -f v4l2 -input_format "$fmt" \
              -video_size "$size" -framerate "$rate" -i "$dev" \
              -c:v ffv1 -level 3 "$out"
          fi
          ;;
        *) usage ;;
      esac
    '';
  };
in {
  options.services.fbtCameras = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = hostName == "zephyr";
      description = ''
        Camera-based full-body-tracking rig support: pinned V4L2 toolchain,
        idempotent exposure locking, and status/verification commands.
        Defaults on for zephyr, the only host with the camera rig attached.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.v4l-utils
      pkgs.ffmpeg
      fbt-cam-lock
      fbt-cam-status
      fbt-cam-verify
      fbt-cam-capture
    ];

    # Session-start lock. Covers boot and re-login. Replug is covered by
    # fbt-cam-capture re-locking immediately before it opens the devices, so a
    # device-event hook (which would have to be a system-level udev rule, i.e.
    # Layer 1) is not required.
    systemd.user.services.fbt-cam-lock = {
      Unit = {
        Description = "Lock FBT camera exposure/gain (prevents auto-exposure framerate halving)";
        After = ["graphical-session.target"];
        PartOf = ["graphical-session.target"];
      };
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${fbt-cam-lock}/bin/fbt-cam-lock";
        # A camera being unplugged is a normal state, not a session failure.
        SuccessExitStatus = "0 1";
      };
      Install.WantedBy = ["graphical-session.target"];
    };
  };
}

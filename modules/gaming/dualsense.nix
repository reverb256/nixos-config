# Fleet-wide Sony DualSense input support.
#
# This module intentionally owns only the input plumbing: it does not enable
# Steam, Gamescope, Bluetooth daemons, or kernel-level deadzone mutation.
{config, lib, pkgs, ...}: let
  cfg = config.services.dualsense;
  diagnostic = pkgs.writeShellScriptBin "dualsense-diagnose" ''
    #!${pkgs.bash}/bin/bash
    set -u

    echo "DualSense diagnostic"
    echo "===================="
    echo "Kernel driver modules:"
    ${pkgs.kmod}/bin/lsmod | ${pkgs.gnugrep}/bin/grep -E '(^| )hid_playstation( |$)|(^| )hid_sony( |$)' \
      || echo "  hid_playstation not loaded"

    echo
    echo "Input devices:"
    found=0
    for device in /sys/class/input/event*; do
      name=$(${pkgs.coreutils}/bin/cat "$device/device/name" 2>/dev/null || true)
      if [[ "$name" == *DualSense* ]]; then
        found=1
        node="/dev/input/$(basename "$device")"
        printf '  %-12s %-8s %s\\n' "$(basename "$device")" "$(stat -c '%A' "$node" 2>/dev/null || echo '?')" "$name"
      fi
    done
    [[ "$found" -eq 1 ]] || echo "  no DualSense input device found"

    echo
    echo "HIDRAW devices:"
    hid_found=0
    for device in /dev/hidraw*; do
      properties=$(${pkgs.systemd}/bin/udevadm info --query=property --name="$device" 2>/dev/null || true)
      if printf '%s\\n' "$properties" | ${pkgs.gnugrep}/bin/grep -qE 'ID_VENDOR_ID=054c|ID_VENDOR_FROM_DATABASE=Sony'; then
        hid_found=1
        printf '  %s %s\\n' "$device" "$(stat -c '%A' "$device" 2>/dev/null || echo '?')"
      fi
    done
    [[ "$hid_found" -eq 1 ]] || echo "  no Sony HIDRAW device found"

    echo
    echo "Bluetooth adapter:"
    if command -v ${pkgs.bluez}/bin/bluetoothctl >/dev/null 2>&1; then
      ${pkgs.bluez}/bin/bluetoothctl show 2>/dev/null \
        | ${pkgs.gnugrep}/bin/grep -E 'Powered|Discoverable|Pairable' || echo "  adapter unavailable"
      echo "Paired Sony devices:"
      ${pkgs.bluez}/bin/bluetoothctl devices 2>/dev/null \
        | ${pkgs.gnugrep}/bin/grep -iE 'Sony|DualSense|054c' || echo "  none found"
    else
      echo "  bluetoothctl unavailable (Bluetooth is optional)"
    fi

    echo
    echo "SDL mapping file:"
    if [[ -s /etc/sdl2-dualsense-db ]]; then
      echo "  /etc/sdl2-dualsense-db present ($(wc -l < /etc/sdl2-dualsense-db) mappings)"
    else
      echo "  /etc/sdl2-dualsense-db missing or empty"
    fi

    echo
    echo "Notes:"
    echo "  USB is recommended for native adaptive triggers and high-definition haptics."
    echo "  Steam Input provides broad Proton compatibility but may virtualize PlayStation features."
    echo "  Deadzones remain userspace-owned by SDL/Steam; no global evdev mutation is applied."
  '';
in {
  options.services.dualsense = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable fleet-wide Sony DualSense input support.";
    };
  };

  config = lib.mkIf cfg.enable {
    # hid-playstation is normally modalias-loaded, but declaring it here makes
    # the fleet contract explicit and supports controllers present early at boot.
    boot.kernelModules = lib.mkOptionDefault ["hid_playstation"];

    # Enable the BlueZ daemon fleet-wide without installing the full gaming
    # stack. Pairing/trust remains per-host user state; servers without an
    # adapter simply have no Bluetooth controller to discover.
    hardware.bluetooth = {
      enable = lib.mkDefault true;
      powerOnBoot = lib.mkDefault true;
    };

    services.udev.extraRules = ''
      # Sony DualSense/DualSense Edge USB and Bluetooth HIDRAW access.
      # uaccess grants the active local desktop user access without a global
      # world-writable device rule; the IDs cover current USB/BT variants.
      SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", MODE="0660", TAG+="uaccess"
      SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0df2", MODE="0660", TAG+="uaccess"
      SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0df5", MODE="0660", TAG+="uaccess"
      SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0df6", MODE="0660", TAG+="uaccess"
    '';

    environment.etc."sdl2-dualsense-db".text = ''
      0300000054c0ce60000000000000000,DualSense Wireless Controller,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,misc1:b1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,platform:Linux,
      0500000054c0ce60000000000000000,DualSense Wireless Controller,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,misc1:b1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,platform:Linux,
      0300000054c00000921000000000000,DualSense Wireless Controller,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,platform:Linux,
      0300000054c00000921000016000000,DualSense Wireless Controller,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,platform:Linux,
      0300000054c00000921000000010000,DualSense Wireless Controller,a:b0,b:b1,back:b4,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b5,leftshoulder:b9,leftstick:b7,lefttrigger:a4,leftx:a0,lefty:a1,rightshoulder:b10,rightstick:b8,righttrigger:a5,rightx:a2,righty:a3,start:b6,x:b2,y:b3,platform:Linux,
    '';

    # SDL2 consumes this mapping file through its standard file override.
    environment.sessionVariables.SDL_GAMECONTROLLERCONFIG_FILE =
      "/etc/sdl2-dualsense-db";

    environment.systemPackages = [diagnostic];
  };
}

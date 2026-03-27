#!/usr/bin/env bash
#
# verify-deadzone.sh - Test if DualSense deadzone is working
#
# Usage: ./verify-deadzone.sh
#

echo "=== DualSense Deadzone Verification ==="
echo ""

# Find the DualSense event device
EVENT_DEVICE=$(ls -la /dev/input/by-id/usb-Sony_Interactive_Entertainment_DualSense_Wireless_Controller-if03-event-joystick 2>/dev/null | awk '{print $NF}')

if [[ -z "$EVENT_DEVICE" ]]; then
  echo "❌ DualSense controller not found!"
  echo "Make sure:"
  echo "  1. Controller is connected (USB or Bluetooth)"
  echo "  2. Controller is paired"
  exit 1
fi

echo "✅ Found controller at: $EVENT_DEVICE"
echo ""

# Check current deadzone settings
echo "Current deadzone settings:"
echo "  Leave sticks centered and press ENTER"
read

sudo /run/current-system/sw/bin/set-evdev-deadzone "$EVENT_DEVICE" 0:20 1:20 3:20 4:20

echo ""
echo "Deadzone applied! Testing..."
echo ""
echo "Instructions:"
echo "  1. Don't touch the sticks (centered position)"
echo "  2. Press ENTER to read centered values"
echo "  3. Gently move left stick in tiny circles (drift test)"
echo "  4. Press ENTER to read drifted values"
echo ""

read -p "Press ENTER to read centered values..."
echo ""
echo "Centered values:"
sudo /tmp/test-deadzone "$EVENT_DEVICE" | grep -E "Axis|Current value"

read -p "Press ENTER when you've moved the sticks slightly..."
echo ""
echo "After drift values:"
sudo /tmp/test-deadzone "$EVENT_DEVICE" | grep -E "Axis|Current value"

echo ""
echo "=== Test Complete ==="
echo ""
echo "If deadzone is working:"
echo "  - Centered values should be ~125-130 (middle of 0-255 range)"
echo "  - Tiny movements (< 20 from center) should be ignored"
echo "  - Only movements beyond ±20 should register"
echo ""
echo "The deadzone setting is shown as 'flat' value in the output above."

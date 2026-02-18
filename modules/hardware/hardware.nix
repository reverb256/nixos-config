# Hardware Module
# Extracted from configuration.nix - Hardware configuration for zephyr workstation
_: {
  # ============================================================================
  # BLUETOOTH SUPPORT
  # ============================================================================

  # Hardware configuration
  hardware = {
    # Enable Bluetooth
    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    # Enable redistributable firmware for better hardware support
    enableRedistributableFirmware = true;

    # NVIDIA settings are host-specific - configured in individual host flakes

    # Graphics configuration
    graphics = {
      enable = true;
      enable32Bit = true; # 32-bit support for Steam/VR
    };
  };
}

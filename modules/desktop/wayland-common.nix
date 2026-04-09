# Wayland Common Infrastructure
# PipeWire, Bluetooth, and common Wayland desktop utilities
_: {
  services = {
    # Enable sound with pipewire
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    # Disable pulseaudio - use PipeWire's PulseAudio replacement
    pulseaudio.enable = false;

    # Enable touchpad support
    libinput.enable = true;

    # Enable dbus-broker
    dbus = {
      enable = true;
      implementation = "broker";
    };

    # Enable printing
    printing.enable = true;
  };

  # Enable RTKit for real-time audio
  security.rtkit.enable = true;
}

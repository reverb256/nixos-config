# Wayland Common Infrastructure
# PipeWire, Bluetooth, and common Wayland desktop utilities
_: {
  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Enable touchpad support
  services.libinput.enable = true;

  # Enable dbus-broker
  services.dbus = {
    enable = true;
    implementation = "broker";
  };

  # Enable printing
  services.printing.enable = true;
}

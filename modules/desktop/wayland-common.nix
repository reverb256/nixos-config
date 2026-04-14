_: {
  services = {
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    pulseaudio.enable = false;

    libinput.enable = true;

    dbus = {
      enable = true;
      implementation = "broker";
    };

    printing.enable = true;
  };

  security.rtkit.enable = true;
}

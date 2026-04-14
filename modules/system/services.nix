{pkgs, ...}: {
  systemd.packages = with pkgs; [
    auto-cpufreq
  ];

  services = {
    upower.enable = true;

    dbus = {
      enable = true;
      implementation = "broker";
      packages = with pkgs; [
        xfconf
        gnome2.GConf
      ];
    };

    mpd.enable = true;

    tumbler.enable = true;

    fwupd.enable = true;

  };

  programs = {
    dconf.enable = true;
    thunar.enable = true;
    xfconf.enable = true;
  };

  environment.systemPackages = with pkgs; [
    qutebrowser

    zathura

    mpv
    imv

    at-spi2-atk

    qt6.qtwayland

    psi-notify
    poweralertd

    playerctl

    psmisc

    grim
    slurp
    imagemagick
    swappy
    ffmpeg_6-full
    wl-screenrec

    wl-clipboard
    wl-clip-persist
    cliphist

    xdg-utils

    wtype
    wlrctl

    waybar
    rofi
    dunst
    avizo
    wlogout

    gifsicle
  ];
}

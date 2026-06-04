{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    parallel
    parallel-full
    fastfetch
    mosh
    nmap
    netcat
    socat
    xh
    hexdump
    xxd
    file
    tree

    networkmanager

    vim
    hostname

    ssh-to-age

    btrfs-progs
    awscli2

    pciutils
    usbutils
    lshw
    dmidecode
    hwinfo
    smartmontools

    perf

    ethtool
    bmon
    iftop
    tcpdump
    mtr
    dnsutils

    parted
    gptfdisk
    rsync
    pv
    progress

    screen

    steam-run
    pkgsi686Linux.glibc

    vulkan-loader
    vulkan-tools

    xrizer
    opencomposite
    vulkan-validation-layers
    vulkan-headers
    dxvk
    wine
    winetricks
    vkbasalt
    obs-studio-plugins.obs-vkcapture

    polychromatic
    razergenie
    razer-cli
    headsetcontrol
    liquidctl

    nh
    home-manager

    xdg-desktop-portal
    flatpak

    nvidia-vaapi-driver
    vdpauinfo
    egl-wayland
    wayland-utils
    localsend

    xrdb
    xrandr
    kdePackages.kscreen
    kdePackages.kio-extras

    wl-clipboard

    ocl-icd
    libclc
    hermes-chat
  ];
}

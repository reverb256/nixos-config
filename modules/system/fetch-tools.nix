{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    fastfetch
    onefetch

    ipfetch
    cpufetch
    ramfetch
    starfetch
    octofetch

    htop
    bottom
    btop
    zfxtop

    kmon

    wlr-randr
    gpu-viewer

    dig
    speedtest-rs

    vulkan-tools
  ];
}

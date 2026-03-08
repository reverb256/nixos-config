# Info Fetchers Module
# Extended system information tools from XNM1
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    # Classic fetch tools
    fastfetch  # Modern replacement for neofetch
    onefetch

    # Hardware-specific fetchers
    ipfetch     # IP information
    cpufetch   # CPU architecture and info
    ramfetch   # RAM information
    starfetch  # Minimalist fetch
    octofetch  # GitHub contribution info

    # System monitors
    htop
    bottom     # Modern top replacement
    btop       # Even more feature-rich
    zfxtop     # ZFS monitoring (useful with your storage)

    # Kernel manager
    kmon       # Interactive Linux kernel manager

    # GPU monitoring
    # NOTE: nvtop temporarily disabled due to cuda_compat build failure in nixpkgs
    # Use gpu-viewer, nvidia-smi (from driver), and btop for monitoring instead
    # nvtopPackages.nvidia    # NVIDIA GPU monitoring - BROKEN DEPS
    # nvtopPackages.intel     # Intel GPU monitoring
    # nvtopPackages.amd       # AMD GPU monitoring

    # Display utilities
    wlr-randr               # Wayland display control
    gpu-viewer              # GPU information viewer

    # Network utilities
    dig                     # DNS lookup
    speedtest-rs            # Rust-based speedtest

    # Vulkan tools (for GPU debugging)
    vulkan-tools
  ];
}

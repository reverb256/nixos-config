# modules/profiles/hardware/default.nix --- Hardware profiles
{lib, ...}: let
  inherit (lib) mkEnableOption;
in {
  imports = [
    ./implementations.nix
    # Import GPU modules so options are available for all hosts
    # Modules only apply when their enable options are set
    ../../hardware/amdgpu-wayland.nix
    ../../hardware/nvidia-wayland.nix
  ];

  options.hardware.profiles = {
    # CPU profiles
    amd = {
      enable = mkEnableOption "AMD CPU optimizations";
      zen = mkEnableOption "Zen CPU specific optimizations";
    };

    intel = {
      enable = mkEnableOption "Intel CPU optimizations";
    };

    # GPU profiles
    nvidia = {
      enable = mkEnableOption "NVIDIA GPU support";
      multiGpu = mkEnableOption "Multi-GPU configuration";
    };

    amdgpu = {
      enable = mkEnableOption "AMD GPU support";
      wayland = mkEnableOption "AMDGPU Wayland optimizations";
    };

    # Other hardware
    corsair = {
      enable = mkEnableOption "Corsair hardware (AIO, RGB)";
    };

    monitoring = {
      enable = mkEnableOption "Hardware monitoring (lm-sensors)";
    };
  };
}

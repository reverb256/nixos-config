{lib, ...}: let
  inherit (lib) mkEnableOption;
in {
  imports = [
    ./implementations.nix
    ../../hardware/amdgpu-wayland.nix
    ../../hardware/nvidia-wayland.nix
  ];

  options.hardware.profiles = {
    amd = {
      enable = mkEnableOption "AMD CPU optimizations";
      zen = mkEnableOption "Zen CPU specific optimizations";
    };

    intel = {
      enable = mkEnableOption "Intel CPU optimizations";
    };

    nvidia = {
      enable = mkEnableOption "NVIDIA GPU support";
      multiGpu = mkEnableOption "Multi-GPU configuration";
    };

    amdgpu = {
      enable = mkEnableOption "AMD GPU support";
      wayland = mkEnableOption "AMDGPU Wayland optimizations";
    };

    corsair = {
      enable = mkEnableOption "Corsair hardware (AIO, RGB)";
    };

    monitoring = {
      enable = mkEnableOption "Hardware monitoring (lm-sensors)";
    };
  };
}

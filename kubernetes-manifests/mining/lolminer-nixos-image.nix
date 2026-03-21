# NixOS-based lolMiner container image
# Uses same GLIBC and libraries as host (NixOS 26.05)
# Solves GLIBC ABI incompatibility with AMD OpenCL libraries
#
# Build: nix-build .#packages.x86_64-linux.lolminer-nixos
# Load: docker load < result
# Tag: docker tag lolminer-nixos:latest localhost/lolminer-nixos:latest
{
  pkgs,
  lib,
  ...
}: let
  # lolMiner wrapper script that sets up the environment
  lolminerWrapper = pkgs.writeShellScriptBin "lolMiner" ''
    #!${pkgs.bash}/bin/bash
    set -e

    # Set up OpenCL ICD path for AMD GPUs
    export OCL_ICD_VENDORS="/etc/OpenCL/vendors"

    # Add ROCm/OpenCL libraries to path
    export LD_LIBRARY_PATH="${pkgs.rocmPackages.clr}/lib:${pkgs.rocmPackages.clr.icd}/lib:${pkgs.mesa.opencl}/lib:$LD_LIBRARY_PATH"

    # Run lolMiner with all arguments passed through
    exec ${pkgs.lolminer}/bin/lolMiner "$@"
  '';

in
  pkgs.dockerTools.buildImage {
    name = "lolminer-nixos";
    tag = "latest";

    # Include lolMiner and AMD OpenCL libraries
    contents = [
      pkgs.bash
      pkgs.coreutils  # for basic commands (ls, cat, etc)
      pkgs.lolminer
      lolminerWrapper
      pkgs.rocmPackages.clr
      pkgs.rocmPackages.clr.icd
      pkgs.mesa.opencl
    ];

    # Set up OpenCL ICD configuration
    config = {
      Cmd = ["${lolminerWrapper}/bin/lolMiner"];
      WorkingDir = "/tmp";
      Env = [
        "OCL_ICD_VENDORS=/etc/OpenCL/vendors"
        "LD_LIBRARY_PATH=${pkgs.rocmPackages.clr}/lib:${pkgs.rocmPackages.clr.icd}/lib"
      ];
      Labels = {
        "version" = "1.98a";
        "description" = "lolMiner NixOS container with AMD OpenCL support";
      };
    };
  }

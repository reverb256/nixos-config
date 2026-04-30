{pkgs, ...}: let
  lolminerWrapper = pkgs.writeShellScriptBin "lolMiner" ''
    #!${pkgs.bash}/bin/bash
    set -e
    export OCL_ICD_VENDORS="/etc/OpenCL/vendors"
    export LD_LIBRARY_PATH="${pkgs.rocmPackages.clr}/lib:${pkgs.rocmPackages.clr.icd}/lib:${pkgs.mesa.opencl}/lib:$LD_LIBRARY_PATH"
    exec ${pkgs.lolminer}/bin/lolMiner "$@"
  '';
in
  pkgs.dockerTools.buildImage {
    name = "lolminer-nixos";
    tag = "latest";
    contents = [
      pkgs.bash
      pkgs.coreutils
      pkgs.lolminer
      lolminerWrapper
      pkgs.rocmPackages.clr
      pkgs.rocmPackages.clr.icd
      pkgs.mesa.opencl
    ];
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

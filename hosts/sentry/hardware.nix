{
  pkgs,
  lib,
  ...
}: {
  hardware.gpu-compute = {
    enable = true;
    rocm.enable = true;
    vulkan.enable = true;
  };

  hardware = {
    btrfs-compression.enable = true;
    monitoring = {
      enable = true;
      autoDetect = false;
      fanControl = false;
    };
    rgb-control = {
      enable = true;
      openrgb.enable = true;
      wraithRgb.enable = true;
      temperatureReactive = {
        enable = true;
        sensor = "cpu";
        thresholds = {
          cool = 45;
          warm = 60;
          hot = 70;
        };
        interval = 5;
      };
    };
  };

  boot.kernelParams = [
    "hugepagesz=1G"
    "hugepages=3"
  ];

  environment = {
    variables = {
      LD_LIBRARY_PATH = lib.mkForce "${pkgs.rocmPackages.clr}/lib:${pkgs.rocmPackages.clr.icd}/lib:${pkgs.mesa.opencl}/lib";
      OCL_ICD_VENDORS = "/etc/OpenCL/vendors";
    };

    systemPackages = with pkgs; [
      rocmPackages.rocm-smi
      rocmPackages.rocminfo
    ];
  };

  systemd.tmpfiles.rules = let
    rocmEnv = pkgs.symlinkJoin {
      name = "rocm-combined";
      paths = with pkgs.rocmPackages; [
        clr
        clr.icd
        rocblas
        hipblas
        rpp
      ];
    };
  in [
    "R /var/lib/etcd - - - - -"
    "L+ /opt/rocm - - - - ${rocmEnv}"
    "L+ /opt/rocm/hip - - - - ${pkgs.rocmPackages.clr}"
  ];
}

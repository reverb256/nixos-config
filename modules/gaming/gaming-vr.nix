# VR configuration — WiVRn, Avahi, SteamVR/OpenXR.
# Extracted from modules/gaming/gaming.nix on 2026-07-29
# per Phase 3 de-monolith plan.
#
# Gated by services.gaming.vr.enable (handled via mkIf below).
# Contains: services (avahi, wivrn, udev), networking.firewall,
# boot.kernelModules, hardware.graphics, environment (sessionVariables,
# systemPackages), gaming-detection + gpu-profile-manager.
{ config, lib, pkgs, ... }:
with lib; let
  cfg = config.services.gaming;
  vrCfg = cfg.vr;
in mkIf vrCfg.enable {
  services = {
    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };
    wivrn = {
      enable = true;
      openFirewall = true;
      autoStart = true;
    };
    udev.extraRules = ''
      SUBSYSTEM=="usb", ATTR{idVendor}=="2833", ATTR{idProduct}=="0181", MODE="0666", TAG+="uaccess"
      SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2101", MODE="0666", TAG+="uaccess"
      SUBSYSTEM=="usb", ATTR{idVendor}=="28de", ATTR{idProduct}=="2102", MODE="0666", TAG+="uaccess"
      SUBSYSTEM=="hidraw", ATTRS{idVendor}=="28de", ATTRS{idProduct}=="2102", MODE="0666", TAG+="uaccess"
      SUBSYSTEM=="usb", ATTR{idVendor}=="0bb4", ATTR{idProduct}=="2c87", MODE="0666", TAG+="uaccess"
    '';
    gaming-detection.enable = true;
    gpu-profile-manager.enable = true;
  };

  networking.firewall = {
    allowedTCPPorts = lib.mkOptionDefault [9757];
    allowedUDPPorts = lib.mkOptionDefault [
      9757 5353 9947 27036 27031
    ];
  };

  boot.kernelModules = [
    "usbhid" "uvcvideo" "nvidia-uvm" "hid-sensor-hub" "uinput"
  ];

  hardware.graphics.extraPackages = with pkgs; [
    freetype fontconfig libpng libjpeg libtiff
  ];

  environment = {
    sessionVariables = {
      OPENVR_API_PATH = "${pkgs.xrizer}/lib/xrizer";
    };
    systemPackages = with pkgs; (
      [
        wivrn openxr-loader opencomposite openvr xrizer motoc
        freetype fontconfig libpng libjpeg libtiff ffmpeg
      ]
      ++ [
        (pkgs.writeShellScriptBin "gpu-profile" ''
          exec ${./scripts/gpu-profiles/switch-profile} "$@"
        '')
      ]
    );
  };
}

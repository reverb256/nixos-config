{lib, ...}: let
  inherit (lib) mkEnableOption;
in {
  imports = [
    ./implementations.nix
  ];

  options.profiles.role = {
    workstation = mkEnableOption "Workstation profile (desktop + development)";
    server = mkEnableOption "Server profile (minimal desktop)";
    mining = mkEnableOption "Mining profile (GPU/CPU mining)";
    gaming = mkEnableOption "Gaming profile (Steam, Lutris, etc.)";
    vr = mkEnableOption "VR profile (WiVRn, SteamVR)";
    desktop = mkEnableOption "Desktop profile (Plasma, Wayland)";
    aiInference = mkEnableOption "AI inference profile (opencode tools; gateway runs in K8s)";
    monitoring = mkEnableOption "Monitoring profile (observability stack)";
  };
}

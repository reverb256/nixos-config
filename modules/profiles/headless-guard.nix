# Headless server guard — disables desktop modules when profiles.role.server is set
{ config, lib, ... }: {
  config = lib.mkIf config.profiles.role.server {
    # Prevent desktop modules from loading on headless servers
    services.xserver.enable = lib.mkForce false;
    services.displayManager.enable = lib.mkForce false;
    services.displayManager.sddm.enable = lib.mkForce false;
    boot.loader.grub.enable = lib.mkForce false;

    # SDDM / display-manager dependencies that sneak in via stylix/home-manager
    services.displayManager.autoLogin.enable = lib.mkForce false;

    # PipeWire — not needed on headless servers
    services.pipewire.enable = lib.mkForce false;
  };
}

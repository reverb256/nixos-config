# Steam Runtime Socket Services
# Provides essential socket services for Steam sandbox communication
{pkgs, ...}: {
  # ============================================================================
  # STEAM RUNTIME SOCKETS
  # ============================================================================
  
  # Steam user socket directory
  systemd.tmpfiles.rules = [
    "d /run/user/%i/steam 0700 %i %i"
    "d /run/user/%i/.cache/steam 0700 %i %i"
    "d /run/user/%i/tmux 0700 %i %i"
  ];
  
  # Steam runtime services
  systemd.services.steam-socket-activation = {
    description = "Steam Socket Activation";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = "yes";
      ExecStart = "${pkgs.writeShellScript "steam-socket-init" ''
        # Create Steam runtime directories
        mkdir -p /run/user/$UID/steam
        mkdir -p /run/user/$UID/.cache/steam
        mkdir -p /run/user/$UID/tmux
        chown $USER:$USER /run/user/$UID/steam
        chown $USER:$USER /run/user/$UID/.cache/steam
        chown $USER:$USER /run/user/$UID/tmux
      ''} $USER";
    };
  };
  
  # Steam runtime environment
  environment.sessionVariables = {
    # Steam runtime environment
    STEAM_RUNTIME = "1";
    STEAM_RUNTIME_PREFER_HOST_LIBRARIES = "0";
    STEAM_RUNTIME_FORCE_HOST = "0";
    
    # Steam socket paths
    XDG_RUNTIME_DIR = "/run/user/${toString 1000}";
    
    # Steam Proton environment
    PROTON_USE_WINED3D = "0";
    DXVK_ASYNC = "1";
    WINE_FULLSCREEN_FORCE_DESKTOP = "1";
    
    # Steam VR environment
    STEAM_LINUX_RUNTIME_VULKAN = "1";
    STEAM_LINUX_RUNTIME_NVAPI = "1";
    
    # Tmux socket path
    TMUX_TMPDIR = "/run/user/${toString 1000}/tmux";
  };
}
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
  
}
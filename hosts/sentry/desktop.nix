{ config, pkgs, lib, ... }: {
  # Enable UWSM (Universal Wayland Session Manager) for proper session management
  programs.uwsm = {
    enable = true;
    waylandCompositors.niri = {
      prettyName = "Niri";
      comment = "A scrollable-tiling Wayland compositor";
      binPath = "/run/current-system/sw/bin/niri-session";
    };
  };

  programs.niri = {
    enable = true;
    # settings removed — niri version mismatch
  };

  desktop.uwsm-sessions.enable = true;

  # NEVER suspend, hibernate, or sleep — ever
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    "hybrid-sleep".enable = false;
  };

  services.logind.settings = {
    Login = {
      HandleLidSwitch = "ignore";
      HandleLidSwitchExternalPower = "ignore";
      HandleLidSwitchDocked = "ignore";
      HandleSuspendKey = "ignore";
      HandleHibernateKey = "ignore";
      HandlePowerKey = "ignore";
      IdleAction = "ignore";
    };
  };

  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id.indexOf("suspend") >= 0 ||
          action.id.indexOf("hibernate") >= 0) {
        return polkit.Result.NO;
      }
    });
  '';
}

{ config, pkgs, lib, ... }: {
  # Enable UWSM (Universal Wayland Session Manager) for proper session management.
  # 2026-07-03: binPath points at the raw `niri` binary rather than the
  # nixpkgs-26.04 `niri-session` wrapper, which conflicts with uwsm's
  # wayland-compositor@.service supervision and times out at ~42 s
  # (sddm-helper exit 64, greeter loop). Same fix applied to zephyr
  # in hosts/zephyr/desktop.nix and the shared modules/desktop/niri.nix.
  programs.uwsm = {
    enable = true;
    waylandCompositors.niri = {
      prettyName = "Niri";
      comment = "A scrollable-tiling Wayland compositor";
      binPath = "/run/current-system/sw/bin/niri";
    };
  };

  programs.niri = {
    enable = true;
    # settings removed — niri version mismatch
  };

  # 2026-07-07: opt out of noctalia v5 daemon. Sentry is a Vulkan AI
  # inference box (RX 5600 XT 6GB) running K3s pods. Wayland session
  # is minimal/inactive most of the time. The shared
  # modules/desktop/wayland-compositor-common.nix mkDefaults noctalia on
  # for every niri-enabled host; we force it off here so the daemon
  # doesn't compete with inference workloads for RAM and GPU focus.
  programs.noctalia.enable = lib.mkForce false;
  programs.noctalia.systemd.enable = lib.mkForce false;

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

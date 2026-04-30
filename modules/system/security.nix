{
  pkgs,
  lib,
  ...
}: {
  environment.systemPackages = with pkgs; [
    fail2ban
    usbguard
    firejail
    bubblewrap

    lynis
    vulnix

    nmap
    wireshark
    tcpdump

    pass
    pass-wayland

    age
    ssh-to-age

    libfido2
    yubikey-personalization

    podman-compose
    podman-tui
    lazydocker
  ];

  services = {
    fail2ban = {
      enable = true;
      maxretry = 3;
      bantime = "4h";

      ignoreIP = [
        "127.0.0.1"
        "::1"
        "10.1.1.0/24"
        "100.64.0.0/10"
        "10.1.1.110"
        "10.1.1.120"
        "10.1.1.130"
        "10.1.1.140"
        "100.81.182.5"
        "100.86.158.18"
        "100.95.222.45"
        "100.82.210.39"
      ];

      jails = {
        sshd = {
          enabled = true;
        };
      };
    };

    usbguard = {
      enable = true;
      implicitPolicyTarget = "block";
      rules = ''
        allow
      '';
    };

    dbus.apparmor = "enabled";
  };

  programs.firejail = {
    enable = true;
    wrappedBinaries = {
      firefox = "${pkgs.firejail}/bin/firejail ${pkgs.firefox}/bin/firefox";
      thunderbird = "${pkgs.firejail}/bin/firejail ${pkgs.thunderbird}/bin/thunderbird";
      vlc = "${pkgs.firejail}/bin/firejail ${pkgs.vlc}/bin/vlc";
    };
  };

  environment.etc."firejail/firejail.conf".text = ''
    quiet

    seccomp

    private-dev

    private-tmp

    no3d

    private-etc hosts,resolv.conf

  '';

  security = {
    sudo-rs = {
      enable = true;
      execWheelOnly = true;
      wheelNeedsPassword = false;
    };
    sudo.enable = lib.mkForce false;

    apparmor = {
      enable = true;
      killUnconfinedConfinables = true;
      packages = with pkgs; [
        apparmor-utils
        apparmor-profiles
      ];
    };

    pam.services = {
      login.enableAppArmor = true;
      sshd.enableAppArmor = true;
      sudo-rs.enableAppArmor = true;
      su.enableAppArmor = true;
    };
  };

  users.users.root.hashedPassword = "!";

  programs.firejail.wrappedBinaries = {
    mpv = {
      executable = "${pkgs.mpv}/bin/mpv";
      profile = "${pkgs.firejail}/etc/firejail/mpv.profile";
    };
    discord = {
      executable = "${pkgs.discord}/bin/discord";
      profile = "${pkgs.firejail}/etc/firejail/discord.profile";
    };
    vscodium = {
      executable = "${pkgs.vscodium}/bin/vscodium";
      profile = "${pkgs.firejail}/etc/firejail/vscodium.profile";
    };
  };

  systemd.services.nixos-upgrade-unit = {
    description = "Notify about available NixOS upgrades";
    serviceConfig.ExecStart = pkgs.writeShellScript "nixos-upgrade-notify" ''
      if [ -n "''${DISPLAY:-}" ] && command -v ${pkgs.libnotify}/bin/notify-send >/dev/null 2>&1; then
        ${pkgs.libnotify}/bin/notify-send "NixOS Updates Available" "Run 'sudo nixos-rebuild switch' to update" -i software-update-available
      fi
    '';
    wantedBy = ["multi-user.target"];
    serviceConfig.Type = "oneshot";
  };
}

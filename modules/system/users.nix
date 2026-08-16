{
  pkgs,
  lib,
  config,
  ...
}: {
  users.users.j_kro = {
    isNormalUser = true;
    description = "Jeremy Kroeker";
    # POSIX login shell so AI agents and SSH sessions get bash-compatible
    # behavior (issue #645). Fish stays enabled for interactive use.
    shell = pkgs.zsh;
    # NOTE (2026-07-21, issue #300): `initialHashedPassword` was the
    # upstream name for "set this hash only on first boot" (now called
    # `initialPassword` for plaintext / `hashedPassword` for hashed).
    # The cluster root+user identity runs on a NixOS upgrade path that
    # already has these hashes applied, so a plain `hashedPassword`
    # keeps the value idempotent at every switch — `initialHashedPassword`
    # fires an assertion under newer NixOS that no option of that name
    # exists.
    hashedPassword = "$y$j9T$JXuhIoBxfLWWZ57CJXtwQ.$cYs3wivkMTdLIvfjng4hzRqQRRdUA2rfCsic6wjRL25";
    extraGroups = [
      "networkmanager"
      "wheel"
      "render"
      "video"
      "libinput"
      "ai-inference"
      "plugdev"
      "openrazer"
      "gamemode"
      "i2c"
      "kvm"
      # Handy STT global hotkeys: rdev needs /dev/uinput (input group +
      # udev rule below) to register system-wide shortcuts on Wayland.
      "input"
    ];
    packages = with pkgs; (
      # Desktop apps only on hosts with a desktop environment
      (lib.optionals (config.programs.niri.enable or false) [
        kdePackages.kate
        kdePackages.yakuake
      ])
      ++ [
        gh
        nodejs
        fastfetch
        zoxide
        fzf
      ]
    );
  };

  users.groups.j_kro = {};

  # Declarative root password (same as j_kro for consistency)
  users.users.root.hashedPassword = "!";

  environment.sessionVariables = lib.mkOptionDefault {
    TZ = "America/Winnipeg";
  };

  security.pam.services.login.setEnvironment = true;

  environment.etc."environment".text = ''
    TZ=America/Winnipeg
  '';

  # Use sudo-rs consistently on every host. Keeping this in the shared user
  # module prevents classic sudo from silently winning on hosts that do not
  # import the larger Forge security profile.
  security.sudo-rs = {
    enable = true;
    execWheelOnly = true;
    wheelNeedsPassword = false;
    extraRules = [
      {
        users = ["j_kro"];
        commands = [
          {
            command = "ALL";
            options = ["NOPASSWD"];
          }
        ];
      }
    ];
  };
  security.sudo.enable = false;

  users.groups.plugdev = {};
  users.groups.gamemode = {};
  # Pin kvm group to a system-range GID (400-999) so udev can resolve it when
  # creating /dev/kvm. Without this, udev's KERNEL=="kvm",GROUP="kvm" rule
  # fails to resolve the out-of-range GID (was 302) and /dev/kvm falls back to
  # restrictive ownership, causing QEMU/KVM "Operation not permitted" in incus.
  users.groups.kvm = { gid = lib.mkForce 998; };
  # incus runs its QEMU feature-check / VM processes as the 'nobody' user
  # (qemu '-runas nobody'). 'nobody' must be in the 'kvm' group or KVM device
  # access is denied (EPERM), which breaks incus VM support entirely.
  users.users.nobody.extraGroups = [ "kvm" ];
  # j_kro already a kvm member via incus-gamepass; ensure root can use KVM too.
  users.users.root.extraGroups = [ "kvm" ];
  users.groups.i2c = {};
  users.groups.input = {};

  # Handy STT (rdev global hotkeys): allow the input group to read/write
  # /dev/uinput so system-wide shortcuts work on Wayland (niri owns the
  # bind; rdev injects via uinput).
  services.udev.extraRules = lib.mkAfter ''
    KERNEL=="uinput", SUBSYSTEM=="misc", GROUP="input", MODE="0660"
  '';
  users.groups.ai-inference = {};
}

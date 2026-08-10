{
  pkgs,
  lib,
  config,
  ...
}: {
  users.users.j_kro = {
    isNormalUser = true;
    description = "Jeremy Kroeker";
    shell = pkgs.fish;
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
  # j_kro already a kvm member via incus-gamepass; ensure root can use KVM too.
  users.users.root.extraGroups = [ "kvm" ];
  users.groups.i2c = {};
  users.groups.ai-inference = {};
}

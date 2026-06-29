{
  pkgs,
  lib,
  ...
}: {
  users.users.j_kro = {
    isNormalUser = true;
    description = "Jeremy Kroeker";
    shell = pkgs.fish;
    initialHashedPassword = "$y$j9T$JXuhIoBxfLWWZ57CJXtwQ.$cYs3wivkMTdLIvfjng4hzRqQRRdUA2rfCsic6wjRL25";
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
    ];
    packages = with pkgs; [
      kdePackages.kate
      kdePackages.yakuake
      gh
      nodejs
    ];
  };

  users.groups.j_kro = {};

  # Declarative root password (same as j_kro for consistency)
  users.users.root.initialHashedPassword = "$y$j9T$JXuhIoBxfLWWZ57CJXtwQ.$cYs3wivkMTdLIvfjng4hzRqQRRdUA2rfCsic6wjRL25";

  environment.sessionVariables = lib.mkOptionDefault {
    TZ = "America/Winnipeg";
  };

  security.pam.services.login.setEnvironment = true;

  environment.etc."environment".text = ''
    TZ=America/Winnipeg
  '';

  security.sudo = {
    enable = lib.mkDefault true;
    extraConfig = ''
      j_kro ALL=(ALL) NOPASSWD: ALL
    '';
  };

  users.groups.plugdev = {};
  users.groups.gamemode = {};
  users.groups.i2c = {};
  users.groups.ai-inference = {};
}
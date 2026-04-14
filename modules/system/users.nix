{
  pkgs,
  lib,
  ...
}:
{
  users.users.j_kro = {
    isNormalUser = true;
    description = "Jeremy Kroeker";
    shell = pkgs.fish;
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

  environment.sessionVariables = lib.mkOptionDefault {
    TZ = "America/Winnipeg";
  };

  security.pam.services.login.setEnvironment = true;

  environment.etc."environment".text = ''
    TZ=America/Winnipeg
  '';

  security.sudo = {
    enable = true;
    extraConfig = ''
      j_kro ALL=(ALL) NOPASSWD: ALL
    '';
  };

  users.groups.plugdev = { };
  users.groups.gamemode = { };
  users.groups.i2c = { };
}

{ pkgs, lib, ... }:
{
  # Mirror modules/system/home-manager.nix: nixcord-config (vesktop) is a
  # zephyr-host service. The standalone HM path evaluates this leaf only when
  # hostName == "zephyr" (see standalone.nix), so enabling here is what makes
  # `home-manager switch --flake .#zephyr` actually link + start the
  # vesktop-autostart systemd user service (otherwise it's never deployed).
  nixcord-config.enable = lib.mkForce true;
  # Mirror modules/system/home-manager.nix: caprine is a zephyr-host
  # service, enabled there via the NixOS HM path. The standalone HM path
  # evaluates this leaf only when hostName == "zephyr" (standalone.nix), so
  # enabling here makes `home-manager switch` deploy caprine-autostart too.
  caprine.enable = lib.mkForce true;
  # NOTE: lutris is intentionally NOT here — it is installed in the Layer-3
  # nix profile (priority 5). Duplicating it in HM home.packages makes HM
  # 26.05's nix-profile backend attempt a second priority-5 install and fail
  # with "conflicting packages have a priority of 5" (same class as the
  # freebuff-desktop collision documented in standalone.nix). Keep it Layer-3
  # only; the binary stays on PATH from the profile.
  home.packages = with pkgs; [
    protonup-qt
    heroic
    mangohud
    vkbasalt
  ];
}

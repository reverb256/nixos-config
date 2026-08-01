{ pkgs, ... }:
{
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

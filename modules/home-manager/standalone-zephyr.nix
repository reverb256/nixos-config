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
  # only; the binary stays on PATH from the profile. (2026-08-04 audit WS2:
  # proper fix is `nix profile remove lutris` BEFORE a switch that adds it
  # here; tracked in docs/audit-2026-08-04-bandaids.md.)
  home.packages = with pkgs; [
    protonup-qt
    heroic
    mangohud
    vkbasalt

    # ── Migrated from the imperative Layer-3 nix profile (audit WS2) ──
    # These were `nix profile install`ed on zephyr; moving them into HM makes
    # them reproducible and rollback-safe. IMPORTANT ORDERING: remove the
    # corresponding entries from the live profile BEFORE `just hm-switch` —
    # HM's nix-profile backend installs home.packages at priority 5, and the
    # imperative entries were installed from a stale `flake:nixpkgs` pin, so
    # same-name/same-priority duplicates fail with "conflicting packages have
    # a priority of 5" (the lutris collision class documented above). Store
    # paths persist until GC, so the brief PATH gap between removal and switch
    # is safe. Removal command (run first):
    #   nix profile remove age age-plugin-yubikey sops secretspec cargo clippy \
    #     rustc kubectl wrangler godot manim evil-winrm freerdp powershell \
    #     pywinrm pypsrp openiscsi pam_u2f fuse libvirt llama-cpp-python
    # `hello`, `cuda_cudart`, `lib` (libcublas) are junk / leftover runtime
    #  libs — remove without replacement.
    age
    age-plugin-yubikey
    sops
    secretspec
    cargo
    clippy
    rustc
    kubectl
    wrangler
    godot
    manim
    evil-winrm
    freerdp
    powershell
    python3Packages.pywinrm
    python3Packages.pypsrp
    openiscsi
    pam_u2f
    fuse
    libvirt
    llama-cpp-python
  ];
}

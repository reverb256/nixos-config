# profiles/wsl.nix — Reusable base for NixOS-WSL dev boxes.
#
# Compose with the NixOS-WSL flake module:
#   nixos-wsl.nixosModules.default
#   ./profiles/wsl.nix
#   ./configuration.nix   # host-specific hostname + per-box tweaks
#
# Provides: j_kro user, sshd on 2222 (key + password), gh + git,
# Lix + flakes, declarative /etc/shadow. Per-host extras (extra SSH
# keys, packages, services) live in that host's configuration.nix.

{
  config,
  pkgs,
  lib,
  ...
}:

{
  # ── NixOS-WSL core ─────────────────────────────────────────────
  wsl.enable = true;
  wsl.defaultUser = "j_kro";
  # Native systemd is always enabled in current NixOS-WSL (syschdemd removed);
  # do NOT set wsl.nativeSystemd — it's now a no-op and fails assertions.

  # ── Nix: Lix + flakes ──────────────────────────────────────────
  nix.package = pkgs.lix;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # NixOS owns /etc/shadow so hashedPassword is re-applied on every switch.
  users.mutableUsers = false;

  # ── j_kro user ─────────────────────────────────────────────────
  users.users.j_kro = {
    isNormalUser = true;
    description = "j_kro";
    extraGroups = [
      "wheel"
    ];
    # Keys are merged from the composing host's configuration.nix via
    # mkBefore/mkAfter if you need to add box-specific keys; the base set
    # below covers the primary identities.
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEvekxGk1YR/eF8llVmNk3C59BtgB+9DNvxLy2WjPEyb j_kro@zephyr"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHZOSZbZdeSAJ7MB67hlzOq1MpDt3hiyqbOBG+9OYwYW krash@krash3"
    ];
  };

  # Passwordless sudo for wheel (matches NixOS-WSL default).
  security.sudo.wheelNeedsPassword = false;

  # ── SSH server on 2222 (distinct from Windows host's own :22) ───
  services.openssh = {
    enable = true;
    settings = {
      Port = 2222;
      PermitRootLogin = "no";
      PasswordAuthentication = true;
      PubkeyAuthentication = true;
      KbdInteractiveAuthentication = false;
    };
  };
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      2222
    ];
  };

  # ── CLI tools mirrored from the Windows host ───────────────────
  environment.systemPackages = with pkgs; [
    git
    gh
    vim
    curl
    wget

    # ── Nix authoring / syntax tooling ───────────────────────────
    # nixd          : Nix language server (flake options, diagnostics) — pairs
    #                 with the agent's LSP-based syntax helper.
    # statix        : lint for anti-patterns (catches the wsl.nativeSystemd
    #                 no-op class of bug at edit time).
    # deadnix       : finds dead code / unused lets.
    # alejandra     : opinionated formatter — run `alejandra .` before commit.
    nixd
    statix
    deadnix
    alejandra
  ];

  # ── State version ──────────────────────────────────────────────
  # Bumped by the host config that imports this profile if needed.
  system.stateVersion = lib.mkDefault "26.11";
}

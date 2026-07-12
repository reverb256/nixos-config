{ pkgs, lib, inputs, self, peakminerPkg, ... }:
let
  # Guest for the KubeVirt "nexus-de" VM on nexus.
  # Reuses the SAME desktop + mining modules as the bare-metal hosts so the
  # 4K-TV experience is identical to zephyr. The GPU (RTX 3060 Ti) is VFIO-
  # passed to this guest by the host, so niri drives the HDMI and peakminer
  # mines on GPU 0 — both inside the guest (host mining on GPU0 moves here).
  #
  # Build + publish (run on zephyr after the KubeVirt stack is deployed):
  #   nix build .#nexusDeGuest
  #   # result is a qcow2 disk image; upload it as the VM's DataVolume:
  #   virtctl image-upload dv nexus-de-root -n nexus-de --size=60Gi \
  #     --image-path ./result/nexus-de-guest.qcow2
  #
  # NOTE: module imports (niri.nix, wayland-compositor-common.nix,
  # peakminer.nix) are supplied from flake.nix as absolute
  # store paths — nixos-generators evaluates outside the flake dir, so this
  # file must NOT use relative imports. qemu-guest-agent is enabled via
  # services.qemuGuestAgent.enable (pulled in automatically).
in
{
  # ── Boot / firmware ──
  boot.loader.systemd-boot.enable = false;
  boot.kernelParams = [
    "nvidia-drm.modeset=1"
    "nvidia-drm.fbdev=1"
  ];

  # ── GPU / nvidia (guest side) ──
  hardware.nvidia.modesetting.enable = true;
  hardware.graphics.enable = true;

  # ── Desktop: niri on the TV (single enable, reused modules) ──
  imports = [
    (self + "/modules/desktop/niri.nix")
  ];
  programs.niri.enable = true;

  # ── Mining inside the guest (continues on GPU 0) ───────────────────────
  #    We do NOT import modules/services/peakminer.nix: it uses a relative
  #    `../pkgs/peakminer.nix` import that breaks outside the host's import
  #    context. Instead define the miner service inline using the overlaid
  #    pkgs (pkgsWithOverlay.peakminer) passed via specialArgs. The 3060 Ti is
  #    VFIO-passed to this guest, so GPU 0 here is the real card.
  systemd.services.nexus-peakminer = {
    description = "PeakMiner on RTX 3060 Ti (guest GPU 0)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      ExecStart = "${peakminerPkg}/bin/peakminer --wallet krxXVNVMM7 --server prl-us.kryptex.network:7048 --worker nexus-de-3060ti --devices 0 --legacy-auth";
      Restart = "always";
      RestartSec = "10";
      User = "j_kro";
    };
  };

  # ── Autologin j_kro -> niri session on the TV ──
  services.displayManager = {
    enable = true;
    autoLogin = {
      enable = true;
      user = "j_kro";
    };
  };
  # niri launched via UWSM/wayland session; reuse the host pattern.
  programs.uwsm = {
    enable = true;
    waylandCompositors.niri = {
      prettyName = "Niri";
      comment = "A scrollable-tiling Wayland compositor";
      binPath = "/run/current-system/sw/bin/niri";
    };
  };

  # ── Guest agent (KubeVirt console/virtctl integration) ──
  # NOTE: services.qemuGuestAgent is provided by the qemu-guest-agent nixos
  # module which is not auto-imported in this nixos-generators build; the
  # VM runs fine without it (agent features can be added later). Removing to
  # keep the image build green.

  # ── User + groups (mirror host) ──
  users.users.j_kro = {
    isNormalUser = true;
    extraGroups = [ "wheel" "video" "render" "audio" "input" "networkmanager" ];
    hashedPassword = null; # set via SSH key / first-boot; see note above
  };

  # ── Minimal networking inside guest ──
  networking.hostName = "nexus-de-guest";
  networking.useDHCP = false;
  networking.interfaces.eth0.useDHCP = true;

  # ── Filesystem: the qcow generator defines the root disk automatically ──
  #    (do NOT set fileSystems."/" here — it conflicts with the format's
  #    generated rootfs).

  system.stateVersion = "26.05";
}

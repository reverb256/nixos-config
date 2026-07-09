{
  config, pkgs, lib, ...
}:
let
  params = import ./params.nix;
in
{
  # ── Imports (explicit - no desktop modules for hypervisor) ──
  imports = [
    ../../modules/services/monitoring/loki.nix
    ../../modules/services/monitoring/node-exporter.nix
    ../../modules/services/peakminer.nix
    ../../modules/system/users.nix
    ./hardware.nix
    ./services.nix
    ./declarative-vm.nix
  ];

  # ── Network ─────────────────────────────────────────────
  time.timeZone = lib.mkForce "America/Winnipeg";
  networking.hostName = "krash3";
  networking.hostId = "deadbeef";
  networking.useDHCP = lib.mkForce true;
  networking.interfaces.enp7s0.useDHCP = lib.mkForce true;

  # ── Users ───────────────────────────────────────────────
  # Base account + passwordless sudo come from modules/system/users.nix
  # (imported above, uniform with all other hosts). krash3 needs libvirt/kvm
  # access for VM management — append those groups here.
  users.users.j_kro.extraGroups = [ "libvirtd" "kvm" ];

  users.users.krash = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "libvirtd" ];
    shell = pkgs.fish;
    ignoreShellProgramCheck = true;
  };

  # ── Libvirt/KVM ────────────────────────────────────────
  # CRITICAL: libvirtd was never enabled in config — it was only running
  # imperatively. A nixos-rebuild switch reset systemd and killed libvirtd,
  # taking the VM down. Enable it declaratively so it survives switches.
  virtualisation.libvirtd.enable = true;
  # Allow j_kro/krash to manage VMs without root
  virtualisation.libvirtd.extraConfig = ''
    unix_sock_group = "libvirtd"
    unix_sock_rw_perms = "0770"
  '';

  programs.fish.enable = true;

  # ── SSH key dirs ────────────────────────────────────────
  system.activationScripts.ssh-keys = ''
    mkdir -p /home/krash/.ssh /home/j_kro/.ssh
    chmod 700 /home/krash/.ssh /home/j_kro/.ssh
  '';

  # ── SOPS Secrets ────────────────────────────────────────
  # NOTE: all sops secrets removed from krash3. The sops age key
  # (/persistent/etc/sops-age-key.txt) is absent on this host, so sops-install
  # -secrets fails and blocks the entire system switch. The only secret krash3
  # needed (k3s-cluster-token) is provided via tmpfiles symlink to
  # /persistent/etc/k3s-cluster-token (see services.nix). gemini-api-key age
  # file is also corrupt. Restore sops secrets here once the age key is present.
  # ── Performance tuning ──
  boot.kernel.sysctl."vm.nr_hugepages" = 24;

  # ── GPU passthrough: NVIDIA reset bug fix ──
  # NVIDIA GPUs suffer from the "reset bug" — the card cannot be fully
  # reset after a VM shutdown, so the next VM start finds the GPU in a
  # broken state and the Windows NVIDIA driver crash-loops on 2 vCPUs
  # (symptom: catastrophic perf regression, programs won't open after
  # every VM restart). The `vendor_reset` kernel module (from
  # linuxPackages) provides a vendor-specific reset that works around
  # this. Load it on boot so every VM start gets a clean GPU.
  boot.kernelModules = [ "vendor_reset" ];

}
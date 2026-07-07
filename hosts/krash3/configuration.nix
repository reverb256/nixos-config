{
  config, pkgs, lib, ...
}:
let
  params = import ./params.nix;
in
{
  # ── Imports ───────────────────────────────────────────────
  imports = [
    ../../modules/default.nix
    ./hardware.nix
    ./services.nix
    ./hardware-configuration.nix
    ./declarative-vm.nix
  ];

  # ── Network ─────────────────────────────────────────────
  time.timeZone = lib.mkForce "America/Winnipeg";
  networking.hostName = "krash3";
  networking.hostId = "deadbeef";
  networking.useDHCP = lib.mkForce true;
  networking.interfaces.enp7s0.useDHCP = lib.mkForce true;

  # ── Users ───────────────────────────────────────────────
  users.users.j_kro = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "libvirtd" "kvm" ];
  };

  users.users.krash = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "libvirtd" ];
    shell = pkgs.fish;
  };

  # ── Desktop disabled on hypervisor ───────────────────────
  programs.niri.enable = lib.mkForce false;
  services.flatpak.enable = lib.mkForce false;
  desktop.uwsm-sessions.enable = lib.mkForce false;

  # ── Legacy inline VM XML (REMOVED - using declarative-vm.nix) ───────
  # The inline XML (400+ lines) has been removed
  # New declarative approach uses params.nix + declarative-vm.nix

  # ── SSH key dirs ────────────────────────────────────────
  system.activationScripts.ssh-keys = ''
    mkdir -p /home/krash/.ssh /home/j_kro/.ssh
    chmod 700 /home/krash/.ssh /home/j_kro/.ssh
  '';

  # ── SOPS Secrets ────────────────────────────────────────
  sops.secrets = {
    "gemini-api-key" = {
      sopsFile = ../../secrets/gemini-api-key.yaml;
      format = "binary";
      path = "/run/secrets/gemini-api-key";
      owner = "j_kro";
      group = "users";
      mode = "0444";
    };
    "k3s-cluster-token" = {
      sopsFile = ../../secrets/k8s/k3s-cluster-token.yaml;
      format = "binary";
      path = "/run/secrets/k3s-cluster-token";
      owner = "root";
      group = "root";
      mode = "0444";
    };
  };
  # ── Performance tuning ──
  boot.kernel.sysctl."vm.nr_hugepages" = 24;

}
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
  users.users.j_kro = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "libvirtd" "kvm" ];
  };

  users.users.krash = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "libvirtd" ];
    shell = pkgs.fish;
    ignoreShellProgramCheck = true;
  };

  programs.fish.enable = true;

  # ── SSH key dirs ────────────────────────────────────────
  system.activationScripts.ssh-keys = ''
    mkdir -p /home/krash/.ssh /home/j_kro/.ssh
    chmod 700 /home/krash/.ssh /home/j_kro/.ssh
  '';

  # ── SOPS Secrets ────────────────────────────────────────
  sops.age.keyFile = "/persistent/etc/sops-age-key.txt";
  sops.secrets = {
    "gemini-api-key" = {
      sopsFile = ../../secrets/gemini-api-key.age;
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
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.initrd-ssh-recovery;
  inherit (lib) mkEnableOption mkOption types mkIf;

  # Generate SSH host key at build time.
  # NixOS's initrd-ssh.nix handles derivation paths natively:
  # it creates boot.initrd.secrets entries automatically.
  initrdHostKey =
    pkgs.runCommand "initrd-ssh-host-key" {
      nativeBuildInputs = [pkgs.openssh];
    } ''
      ssh-keygen -t ed25519 -f $out -N "" >/dev/null 2>&1
      chmod 600 $out
    '';
in {
  options.services.initrd-ssh-recovery = {
    enable = mkEnableOption "SSH access in initrd for remote boot recovery";

    port = mkOption {
      type = types.port;
      default = 2222;
      description = "SSH port in initrd (separate from main sshd on 22)";
    };

    networkDriver = mkOption {
      type = types.str;
      default = "r8169";
      description = "Kernel module for the NIC (must be in initrd)";
    };

    interface = mkOption {
      type = types.str;
      default = "eth0";
      description = "Network interface name for initrd IP config";
    };

    authorizedKeys = mkOption {
      type = types.listOf types.str;
      default = config.users.users.j_kro.openssh.authorizedKeys.keys;
      description = "SSH public keys for initrd root login";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = config.boot.initrd.systemd.enable;
        message = "initrd-ssh-recovery requires boot.initrd.systemd.enable = true";
      }
    ];

    boot.initrd = {
      availableKernelModules = [cfg.networkDriver];

      network = {
        enable = lib.mkDefault true;
        ssh = {
          enable = lib.mkDefault true;
          inherit (cfg) port;
          # Pass derivation directly - NixOS handles secrets mapping natively
          hostKeys = [initrdHostKey];
          inherit (cfg) authorizedKeys;
        };
      };

      systemd = {
        enable = lib.mkDefault true;
        initrdBin = with pkgs; [
          btrfs-progs
          coreutils
          findutils
          util-linuxMinimal
          gnugrep
          gnused
        ];
      };
    };

    boot.kernelParams = let
      hostName = config.networking.hostName;
      cluster = config.networking.cluster;
      hostCfg = cluster.hosts.${hostName};
    in [
      "ip=${hostCfg.ip}::${cluster.gateway}:255.255.255.0:${hostName}:${cfg.interface}:none"
    ];

    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [cfg.port];
  };
}

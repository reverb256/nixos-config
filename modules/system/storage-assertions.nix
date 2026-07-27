# ─────────────────────────────────────────────────────────────────
# storage-assertions.nix — Build-time assertions for storage config.
# Catches: wrong partlabel names, missing neededForBoot, UUID paths,
# missing x-initrd.mount on systemd-initrd hosts.
# Include: imports = [ ../../modules/system/storage-assertions.nix ];
# Enable: services.storage-assertions.enable = true;
# ─────────────────────────────────────────────────────────────────
{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.storage-assertions;
in {
  options.services.storage-assertions.enable = mkEnableOption "Build-time storage config assertions";

  config = mkIf cfg.enable {
    assertions =
      # 1. by-partlabel must follow disko "disk-{name}-{part}" format
      (mapAttrsToList (name: fs:
        let
          dev = fs.device;
          isPartlabel = hasPrefix "/dev/disk/by-partlabel/" dev;
          pl = removePrefix "/dev/disk/by-partlabel/" dev;
          ok = builtins.match "disk-.+-.+" pl != null;
        in {
          assertion = !isPartlabel || ok;
          message = "Storage: ${name} partlabel '${pl}' must match disk-{disk}-{part} format.";
        }) config.fileSystems)
      # 2. No by-uuid on BOOT-CRITICAL paths (/, /boot, /nix).
      ++ (mapAttrsToList (name: fs: {
        assertion =
          if (name == "/" || name == "/boot" || name == "/nix")
          then !hasPrefix "/dev/disk/by-uuid/" fs.device
          else true;
        message = "Storage: ${name} uses by-uuid — use by-partlabel for boot-critical mounts.";
      }) config.fileSystems)
      # 3. /nix needs neededForBoot
      ++ (optional (config.fileSystems ? "/nix") {
        assertion = config.fileSystems."/nix".neededForBoot or false;
        message = "Storage: /nix must have neededForBoot = true.";
      })
      # 4. Network/remote filesystems MUST have nofail (never block boot)
      ++ (filter (x: x != null) (mapAttrsToList (name: fs:
        let
          localTypes = ["ext4" "btrfs" "vfat" "xfs" "zfs" "tmpfs" "ramfs" "devtmpfs" "proc" "sysfs" "cgroup2" "autofs" "none" "overlay" "fuse.overlayfs" "squashfs" "securityfs" "debugfs" "pstore" "efivarfs" "hugetlbfs" "mqueue" "configfs" "tracefs" "binfmt_misc" "fuse.lxcfs"];
          isLocal = builtins.elem fs.fsType localTypes;
          hasNofail = builtins.elem "nofail" (fs.options or []);
          hasXinitrd = builtins.elem "x-initrd.mount" (fs.options or []);
        in
        if !isLocal && !hasNofail && !hasXinitrd then {
          assertion = false;
          message = "BOOT BLOCKER: ${name} (${fs.fsType}) is a non-local filesystem without nofail - add nofail to options or this will block boot.";
        } else null
      ) config.fileSystems))
      # 5. systemd-initrd needs x-initrd.mount on /nix
      ++ (optional (config.boot.initrd.systemd.enable or false && config.fileSystems ? "/nix") {
        assertion = any (o: o == "x-initrd.mount") (config.fileSystems."/nix".options or []);
        message = "Storage: /nix needs x-initrd.mount for systemd-initrd.";
      });
  };
}

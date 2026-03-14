# Custom Package Overlay
_: prev: {
  lolminer = prev.callPackage ./packages/lolminer.nix {};
  xmrig = prev.callPackage ./packages/xmrig.nix {};
  # LM Studio - both names point to the same custom package
  lmstudio = prev.callPackage ./packages/lmstudio.nix {};
  lm-studio = prev.callPackage ./packages/lmstudio.nix {};
  # WiVRn with Lighthouse support for Tundra trackers
  wivrn = prev.wivrn.overrideAttrs (old: {
    cmakeFlags = old.cmakeFlags ++ ["-DWIVRN_FEATURE_STEAMVR_LIGHTHOUSE=ON"];
  });
  # assimp: Disable doCheck for x86-64-v3 builds
  # Tests fail due to FMA-induced floating point differences
  # See: https://github.com/assimp/assimp/issues/5687
  assimp = prev.assimp.overrideAttrs (old: {
    doCheck = false;
  });

  # steam-run: Fix bubblewrap issue with NFS autofs mounts
  # Patch steam-run to ignore /data and /etc/nixos from auto-mounting
  # This fixes anime-game-launcher and similar launchers that use steam-run
  steam-run = prev.runCommand "steam-run-patched" {
    nativeBuildInputs = [prev.bash prev.coreutils];
    preferLocalBuild = true;
  } ''
    mkdir -p $out/bin
    # Patch steam-run to ignore /data (NFS autofs) and /etc/nixos (NFS mount)
    sed 's|ignored=(/nix /dev /proc /etc /tmp)|ignored=(/nix /dev /proc /etc /tmp /data /etc/nixos)|' \
      ${prev.steam-run}/bin/steam-run > $out/bin/steam-run
    chmod +x $out/bin/steam-run
  '';
}

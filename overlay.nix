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
}

# Shared Mining Package Overlay
# Consolidates mining package definitions to eliminate duplication across hosts
_: prev: {
  # Custom mining packages with steam-run compatibility
  lolminer = prev.callPackage ../packages/lolminer.nix {};
  xmrig = prev.callPackage ../packages/xmrig.nix {};

  # WiVRn with Lighthouse support for Tundra trackers
  wivrn = prev.wivrn.overrideAttrs (old: {
    cmakeFlags =
      old.cmakeFlags
      ++ [
        "-DWIVRN_FEATURE_STEAMVR_LIGHTHOUSE=ON"
      ];
  });
}

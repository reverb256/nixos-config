{ inputs, _final, prev }:
{
  gputemps = prev.callPackage ../packages/gputemps.nix {};
  lmstudio = prev.callPackage ../packages/lmstudio.nix {};
  peakminer = prev.callPackage ../pkgs/peakminer.nix {};
  secretspec = prev.callPackage ../pkgs/secretspec {inherit inputs;};
  secretspec-provider-sops = prev.callPackage ../pkgs/secretspec-provider-sops {inherit inputs;};
  haven-desktop = prev.callPackage ../packages/haven-desktop.nix {};
  kokoro-tts = prev.callPackage ../packages/kokoro-tts.nix {};
  chatterbox-tts = prev.callPackage ../packages/chatterbox-tts.nix {};
  wivrn = prev.wivrn.overrideAttrs (old: {
    cmakeFlags = old.cmakeFlags ++ ["-DWIVRN_FEATURE_STEAMVR_LIGHTHOUSE=ON"];
  });
  # Proton-GE-RTSP — Proton-GE fork with hardware video decode (h264/RTMP)
  # for VRChat in-world video players. Consumed via
  # programs.steam.extraCompatPackages only (see modules/gaming/gaming-vr-unlock.nix).
  proton-ge-rtsp = prev.callPackage ../packages/proton-ge-rtsp.nix {};
  niri-hdr = prev.callPackage ../pkgs/niri-hdr.nix { inherit (prev) niri-unstable; };
  assimp = prev.assimp.overrideAttrs (_old: { doCheck = false; });
  # 2026-08-04: cups notifier-permission fix REMOVED from build phase.
  # The build-time `overrideAttrs { postInstall = chmod notifier dirs }` forked
  # the cups derivation from the cached upstream path. Since cups is a transitive
  # dep of the Qt6/v4l-utils/gtk3/mesa graphics stack, this ONE override caused
  # the entire desktop graphics closure to recompile from source on every build
  # (mesa ~5662 units) because cups was homelab-unique and absent from cache.nixos.org.
  # The runtime fix is ALREADY covered declaratively by the tmpfiles rule in
  # modules/system/boot-error-fixes.nix ("Z+ .../notifier/dbus 0555 root root").
  # Removing the override lets cups substitute from cache.nixos.org, un-forking
  # mesa/gtk3/qtbase/v4l-utils. Verified: cups/mesa drv now == cached path;
  # mesa narinfo HTTP 200. If cupsd ever complains about notifier ownership,
  # extend the tmpfiles rule instead of reintroducing a build-phase fork.
  dufs = prev.dufs.overrideAttrs (old: {
    doCheck = false;
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [prev.cacert];
  });
  freebuff-desktop = prev.callPackage ../packages/freebuff-desktop.nix {};
  herdr = prev.callPackage ../packages/herdr.nix {};
  llama-cpp = prev.callPackage ../packages/llama-cpp.nix {
    cudaSupport = true;
    inherit (prev) cudaPackages;
  };
  llama-cpp-ik = prev.callPackage ../packages/llama-cpp-ik.nix {};
  llama-cpp-rocm = prev.callPackage ../packages/llama-cpp-rocm.nix {};
  llama-cpp-vulkan = prev.callPackage ../packages/llama-cpp-vulkan.nix {};
  llama-cpp-vulkan-nocuda = prev.callPackage ../packages/llama-cpp-vulkan-nocuda.nix {};
  nixos-cluster-mcp = prev.callPackage ../packages/nixos-cluster-mcp {};
  privacy-filter = prev.callPackage ../packages/privacy-filter.nix {
    transformers-dev = prev.callPackage ../packages/transformers-dev.nix {};
  };
  hermes-chat = prev.callPackage ../packages/hermes-chat.nix {};
}

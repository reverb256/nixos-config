{ inputs, _final, prev }:
{
  gputemps = prev.callPackage ../packages/gputemps.nix {};
  lmstudio = prev.callPackage ../packages/lmstudio.nix {};
  srbminer-multi = prev.callPackage ../packages/srbminer.nix {};
  lpminer-pearl = prev.callPackage ../packages/lpminer.nix {};
  peakminer = prev.callPackage ../pkgs/peakminer.nix {};
  secretspec = prev.callPackage ../pkgs/secretspec { inherit inputs; };
  secretspec-provider-sops = prev.callPackage ../pkgs/secretspec-provider-sops { inherit inputs; };
  haven-desktop = prev.callPackage ../packages/haven-desktop.nix {};
  kokoro-tts = prev.callPackage ../packages/kokoro-tts.nix {};
  chatterbox-tts = prev.callPackage ../packages/chatterbox-tts.nix {};
  wivrn = prev.wivrn.overrideAttrs (old: {
    cmakeFlags = old.cmakeFlags ++ ["-DWIVRN_FEATURE_STEAMVR_LIGHTHOUSE=ON"];
  });
  niri-hdr = prev.callPackage ../pkgs/niri-hdr.nix { inherit (prev) niri-unstable; };
  assimp = prev.assimp.overrideAttrs (_old: { doCheck = false; });
  cups = prev.cups.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      find "$out" -path "$out/share" -prune -o -type d -name notifier -print 2>/dev/null \
        | while read -r d; do [ -d "$d" ] && chmod 0755 "$d"; done || true
    '';
  });
  dufs = prev.dufs.overrideAttrs (old: {
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

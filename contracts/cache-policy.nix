# Canonical binary-cache policy for issue #415.
#
# The objective is upstream derivation identity, not merely finding a copy in
# the local cluster cache. Keep public upstream/specialized caches ahead of the
# cluster cache; reverb-os is for intentional custom artifacts only.
{
  substituters = [
    "https://cache.nixos.org?priority=10"
    "https://cache.nixos-cuda.org?priority=20"
    "https://nix-community.cachix.org?priority=30"
    "https://colmena.cachix.org?priority=30"
    "https://niri.cachix.org?priority=35"
    "https://noctalia.cachix.org?priority=35"
    "https://nix-gaming.cachix.org?priority=35"
    "https://ezkea.cachix.org?priority=35"
    "https://maplespike.cachix.org?priority=35"
    "https://reverb-os.cachix.org?priority=80"
    "http://10.1.1.120:50000?priority=90&want-mass-query=true"
  ];

  trustedPublicKeys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "cache.nixos-cuda.org-1:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "colmena.cachix.org-1:7BzpDnjjH8ki2CT3f6GdOk7QAzPOl+1t3LvTLXqYcSg="
    "niri.cachix.org-1:Wv0O6Tz6V5fM6gD8hIRwM+QjRtBu5OD5QyQjx2hE8vE="
    "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    "nix-gaming.cachix.org-1:vn/szNT7r/Pc1FbcBjRGHLk7XNk0v2KvMq2v7EwXQ8w="
    "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
    "maplespike.cachix.org-1:P6v8AHkRYDKI/xc4/OYIvMcwumkD9EafWnYERWWngYg="
    "reverb-os.cachix.org-1:dctKtu02bV/4fbsYbGuVVxQo9R7X6lNqUet1qj2jYzI="
    "zephyr-cache-1:rDatmGO1sjYLUYCPxA3OAdkb88LmJdJiCy1DFtwftWU="
    "nexus-cache-1:mKdZqDFeOn2nbSVa7GlSEQmyFnZ22AOOB/Wx10YHHNo="
  ];

  # Names are intentionally explicit: these derivations are not expected to
  # match cache.nixos.org because they carry local source/build modifications.
  intentionalCustomPackages = [
    "niri-hdr"
    "llama-cpp"
    "llama-cpp-rocm"
    "llama-cpp-vulkan"
    "llama-cpp-vulkan-nocuda"
    "qwen-tts"
    "faster-whisper"
    "edge-tts"
    "webkitgtk"
    "caddy"
    "assimp"
    "dufs"
    "ckb-next"
  ];

  # These caches are specialized upstream/community sources. Presence is
  # audited at runtime; no coverage is assumed for every package/version.
  specializedCaches = {
    cuda = "https://cache.nixos-cuda.org";
    nixCommunity = "https://nix-community.cachix.org";
    niri = "https://niri.cachix.org";
    noctalia = "https://noctalia.cachix.org";
    nixGaming = "https://nix-gaming.cachix.org";
  };
}

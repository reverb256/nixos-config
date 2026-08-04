{
  # One source of truth for cache endpoints and their verification keys.
  # The Zephyr endpoint is the cluster's signed LAN cache; Cachix entries are
  # public pull caches. Keep endpoint ownership and key identity together.
  substituters = [
    "http://10.1.1.110:50000?priority=40&want-mass-query=true"
    "https://cache.nixos.org?priority=90"
    "https://nix-community.cachix.org?priority=80"
    "https://reverb-os.cachix.org?priority=75"
    "https://maplespike.cachix.org?priority=70"
    "https://ezkea.cachix.org?priority=65"
    "https://nix-gaming.cachix.org?priority=60"
    "https://niri.cachix.org?priority=55"
    "https://noctalia.cachix.org?priority=50"
  ];

  trustedPublicKeys = [
    "zephyr-cache-1:rDatmGO1sjYLUYCPxA3OAdkb88LmJdJiCy1DFtwftWU="
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "reverb-os.cachix.org-1:dctKtu02bV/4fbsYbGuVVxQo9R7X6lNqUet1q2jYzI="
    "maplespike.cachix.org-1:P6v8AHkRYDKI/xc4/OYIvMcwumkD9EafWnYERWWngYg="
    "ezkea.cachix.org-1:ioBmUbJTZIKsHmWWXPe1FSFbeVe+afhfgqgTSNd34eI="
    "nix-gaming.cachix.org-1:vn/szNT7r/Pc1FbcBjRGHLk7XNk0v2KvMq2v7EwXQ8w="
    "niri.cachix.org-1:Wv0O6Tz6V5fM6gD8hIRwM+QjRtBu5OD5QyQjx2hE8vE="
    "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
  ];

  # The LAN cache must serve narinfos signed by this key before
  # `require-sigs = true` is activated on a host.
  local = {
    endpoint = "http://10.1.1.110:50000";
    publicKey = "zephyr-cache-1:rDatmGO1sjYLUYCPxA3OAdkb88LmJdJiCy1DFtwftWU=";
  };
}

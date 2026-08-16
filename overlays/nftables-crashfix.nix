{
  inputs,
  _final,
  prev,
}: {
  nftables = prev.nftables.overrideAttrs (old: {
    src = prev.fetchgit {
      url = "https://git.netfilter.org/nftables.git";
      rev = "refs/heads/master";
      sha256 = "sha256-n4/1tL60vPrwjWa+WXtxBajjLGz6aOheX5/l76GYurU=";
    };
    version = "4f54425e";
    pname = "nftables-master";
  });
}

{ inputs, _final, prev }:
{
  firefoxpwa-unwrapped = prev.firefoxpwa-unwrapped.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      mkdir -p $out/lib/firefoxpwa
    '';
  });
  claude-code-image = prev.callPackage ../packages/claude-code-image.nix {};
  opencode-image = prev.callPackage ../packages/opencode-image.nix {};

  # ckb-next: update to latest upstream (post PR #1323 fix for macro field crash).
  # Nixpkgs snapshot (2025-09-25) has a GUI crash when old 4-field macros are
  # saved. PR #1323 (merged 2026-06-01) checks the macro field count before
  # accessing the 5th delay field. Latest upstream: 2026-07-20.
  ckb-next = prev.ckb-next.overrideAttrs (old: {
    version = "0.6.2-unstable-2026-07-20";
    src = prev.fetchFromGitHub {
      owner = "ckb-next";
      repo = "ckb-next";
      rev = "833ab50951e230674bda02e8448ef6ef365dfd81";
      hash = "sha256-iviGk8Zg/Iou/DvR/4fIQ5Ta5jxbHGUCnCvTLXJdhi0=";
    };
  });
}

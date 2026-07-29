{ inputs, _final, prev }:
{
  firefoxpwa-unwrapped = prev.firefoxpwa-unwrapped.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      mkdir -p $out/lib/firefoxpwa
    '';
  });
  claude-code-image = prev.callPackage ../packages/claude-code-image.nix {};
  opencode-image = prev.callPackage ../packages/opencode-image.nix {};
}

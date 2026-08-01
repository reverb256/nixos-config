{ pkgs, lib, ... }:
{
  # NOTE: Mining CLI tools (lolMiner, t-rex) are intentionally NOT managed by
  # Home Manager here. They are unavailable / marked broken in the current
  # nixpkgs (t-rex refuses evaluation) and belong in Layer 3 (nix profile),
  # where a working flake/overlay can be pinned independently of the HM cadence.
  # HM (Layer 2) owns config + stable user packages; mining binaries are
  # deployed ad-hoc via `nix profile install` (Layer 3).
  home.packages = with pkgs; [
    nvtopPackages.full
    gpustat
  ];

  # Optional mining-tool config seeds — only applied when the source file exists
  # in the flake tree (pre-existing gap: mining/ dir not committed). Resilient so
  # the standalone HM layer builds regardless.
  home.file.".config/nvtop.conf" = lib.mkIf (builtins.pathExists ../../mining/nvtop.conf) {
    source = ../../mining/nvtop.conf;
  };
  xdg.configFile."mining/pools.json" = lib.mkIf (builtins.pathExists ../../mining/pools.json) {
    source = ../../mining/pools.json;
  };
}

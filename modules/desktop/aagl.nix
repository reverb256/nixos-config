{ lib, ... }:
{
  # aagl (Gtk app wrapper) tracks its own 26.11 release branch while we stay on
  # Nixpkgs 26.05. The branch-mismatch check is a warning; we intentionally run
  # aagl ahead of Nixpkgs, so disable the check rather than chase a matching
  # aagl release that may not be published for 26.05.
  aagl.enableNixpkgsReleaseBranchCheck = false;
}

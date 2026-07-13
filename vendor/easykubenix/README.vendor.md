# Vendored: easykubenix

This directory contains a vendored copy of
[Lillecarl/easykubenix](https://github.com/Lillecarl/easykubenix)
at commit `88a025fc04889f25b702f79030c6220c3ec48f9b`.

## Why vendored?

The upstream GitHub fetch was causing `nixos-rebuild` to hang/time out while
resolving the flake input. Vendoring the small (~17 KB) source tree makes the
NixOS evaluation fully offline and immune to GitHub availability/rate-limit
issues for this dependency.

## How to update

1. Find the desired commit hash from upstream.
2. Run:
   ```bash
   cd /etc/nixos/vendor
   rm -rf easykubenix
   curl -sL --connect-timeout 30 --max-time 120 \
     'https://github.com/Lillecarl/easykubenix/archive/<COMMIT>.tar.gz' |
     tar -xz --strip-components=1
   ```
3. Stage the changes and run `nixos-rebuild build --flake .#<host>` to verify.

## License

See the original repository for licensing terms. The vendored files retain the
license headers present in the upstream source.

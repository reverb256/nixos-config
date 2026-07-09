# Stub: thumbnail-service
#
# Intended purpose: serve generated thumbnails for the Glance dashboard
# (`dashboard.lan`) so the homepage tiles render previews without scraping
# upstream. Not yet implemented — Glance currently fetches origin favicons
# on every tile load, which is slow over Tor. Decide whether to ship an inline
# Nix-built service or keep as-is.
{ ... }: { }

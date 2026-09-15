# Homelab Root CA — fleet trust anchor for *.lan / *.media.lan HTTPS.
#
# The Homelab Root CA (see certs/homelab-ca.crt) signs the *.lan wildcard cert
# served by the media stack reverse proxy on nexus and other .lan TLS
# endpoints. Installing it in the system trust store (security.pki) makes
# curl / browsers / language runtimes accept https://<name>.lan without
# certificate warnings.
#
# Only the PUBLIC certificate lives here — private key material stays in
# nixos-secrets. NixOS merges security.pki.certificateFiles across modules,
# so this composes with cluster-ca.nix / caddy-ca.nix.
{ ... }:
{
  security.pki.certificateFiles = [ ./../../certs/homelab-ca.crt ];
}

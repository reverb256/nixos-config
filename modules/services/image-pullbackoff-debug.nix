# Stub: image-pullbackoff-debug
#
# Intended purpose: provide a triage helper for ImagePullBackOff issues on k3s
# workers (mirror-image, registry creds, insecure-registry allowlist). Not yet
# implemented — kept as a placeholder while we decide whether to bake into a
# systemd service or a kubectl alias. Drop `lib` from the lambda since this
# module has no body (suppresses deadnix warning).
{ ... }: { }

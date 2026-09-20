# Workflows here are DISABLED (2026-09-20)

Every workflow file in this directory targets **self-hosted runners tagged `nixos`**
(`runs-on: [self-hosted, nixos]`). Those runners do not exist anymore: the fleet is
Omarchy-only, there are no NixOS machines, and no runner is registered. Any run
triggered on this repo would queue forever (this repo was the worst offender —
scheduled Cluster Status runs queued every few minutes).

Server-side state was set with `gh workflow disable` (files kept for reference).
Do not re-enable a workflow until it is retargeted to a runner that actually exists.

This repo is being retired: see the README banner and Reverb-OS#12.

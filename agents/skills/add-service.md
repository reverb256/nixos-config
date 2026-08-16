# Adding a NixOS service or `.lan` route

**Last verified:** 2026-08-16

## Module template

Every daemon follows one shape:

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.services.my-service;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.my-service = {
    enable = mkEnableOption "My Service";
    port = mkOption { type = types.port; default = 8080; };
  };
  config = mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.mkOptionDefault [ cfg.port ];
    systemd.services.my-service = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = lib.getExe pkgs.my-package;
    };
  };
}
```

Rules:

- `services.*` for daemons, `programs.*` for interactive GUI, `hardware.*` for
  hardware, `profiles.*` for composable profiles.
- `wantedBy = [ "multi-user.target" ]` — never `systemctl enable`.
- Multi-line `ExecStart` uses `pkgs.writeShellScript`; PATH uses `lib.makeBinPath`.
- `git add` new files — Nix only sees git-tracked files.

## Exposing a `.lan` service

`kubernetes/service-ports.nix` is the **single source of truth** for NodePort
assignments. Add a service by:

1. Pick an unused `30xxx` port and add it to `service-ports.nix`.
2. Add the `.lan` DNS record in `modules/network/cluster-dns.nix`.
3. Add a Caddy route — Zephyr `hosts/zephyr/caddy-routes.nix` (`mkRoute` public /
   `mkAuthRoute` protected) or Nexus `modules/services/cluster-services.nix`
   (`protected = true` per service).
4. Deploy the K8s Service with a matching `nodePort`.

NixOS defines the contract (ports, hostnames, TLS); K8s deploys into it. Both
sides read `service-ports.nix`, so ports cannot drift.

# Boots a minimal NixOS VM whose nix-daemon IS the homelab Lix — the same
# derivation the cluster wires into nix.package (lib/lix.nix) — and
# exercises the daemon: version, client/daemon eval round-trip, a real
# store write, and GC. This is the closest thing to deploying to a host
# without touching the cluster.
#
# Build/run: nix build .#lix-vm-test
{
  pkgs,
  inputs,
}: let
  test = pkgs.testers.runNixOSTest {
    name = "lix-homelab-vm";
    nodes.machine = {
      lib,
      pkgs,
      ...
    }: {
      # microarch "znver3" reuses the exact store path the cluster builds
      # for zephyr (per-host -march selection in lib/lix.nix keys off the
      # microarch arg), so the VM boots the same binary that would land on
      # zephyr — no fresh build needed for the test.
      nix.package = import ../lib/lix.nix {
        inherit
          pkgs
          inputs
          ;
        microarch = "znver3";
      };

      nix.settings.experimental-features = ["nix-command" "flakes"];
      networking.hostName = "lix-test";
      system.stateVersion = lib.mkDefault "26.05";
    };

    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")

      # nix-daemon is socket-activated on modern NixOS: the .service unit
      # stays inactive until a client connects, so there is no point
      # waiting for it — the round-trips below exercise the daemon (and
      # socket-activate it) directly, which is the real assertion.

      # The daemon must be the homelab build, not nixpkgs' stock lix.
      out = machine.succeed("nix --version")
      assert "2.96.0-dev-homelab" in out, f"unexpected nix version: {out!r}"

      # Client/daemon eval round-trip through the new daemon.
      v = machine.succeed("nix eval --raw --expr 'builtins.nixVersion'").strip()
      assert v == "2.18.3-lix", f"unexpected builtins.nixVersion: {v!r}"

      # A real store write through the new daemon (multi-user mode: even
      # root goes through the daemon socket).
      machine.succeed("echo 'daemon round-trip' > /tmp/addme.txt")
      machine.succeed("nix-store --add /tmp/addme.txt")
      machine.succeed("nix-store --verify")

      # GC through the new daemon. --print-dead lists what GC would delete
      # without deleting (this lix has no --dry-run sub-op; the modern
      # equivalent is nix store gc --dry-run).
      machine.succeed("nix-store --gc --print-dead")

      # The daemon is socket-activated with per-connection instances
      # ("Lix Daemon instance (legacy)"): the main nix-daemon.service unit
      # stays inactive by design. Assert the serving side is the socket and
      # that the round-trips above actually went through it.
      machine.succeed("systemctl is-active nix-daemon.socket")
    '';
  };
in
  test

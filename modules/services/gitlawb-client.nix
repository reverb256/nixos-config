# Gitlawb CLIENT — `gl` CLI + `git-remote-gitlawb` helper + node endpoint.
#
# SHAPE: this is a CLASSIC NixOS module (options/config), not a flake-parts
# module. That is deliberate. modules/lib/collect-modules.nix recursively walks
# modules/** and feeds every .nix into `imports`; `services/` is not in its
# skipDirs. A file here that set `flake.modules.nixos.*` would be loaded as a
# NixOS module and fail with "The option 'flake' does not exist". Only
# modules/hosts/*/default.nix register flake.* keys, because modules/hosts is
# imported directly by flake.nix, outside the collector's walk. This matches the
# repo's documented migration stance: structure first, shared files last.
#
# ACTIVATION: auto-collected, so it is always LOADED, but it declares
# `enable = false` by default and therefore does nothing until a host opts in.
# Opt in per host with `services.gitlawb-client.enable = true;`.
#
# WHY THIS IS SEPARATE FROM modules/services/gitlawb-node.nix:
#   gitlawb-node.nix runs the SERVER half (podman node + postgres; sentry only).
#   This module is the CLIENT half: the CLI, the git remote helper, and the
#   GITLAWB_NODE endpoint. The build host needs the client and must NOT run a
#   node; sentry needs both. Separate features keep that asymmetry explicit.
#
# WHY THE BUILD HOST NEEDS IT:
#   The homelab Lix fork accepts `gitlawb://` flake-input URLs (scheme whitelist
#   in libfetchers/git.cc). Lix then shells out to the git CLI, and git locates a
#   remote helper by NAME on PATH (`git-remote-<scheme>`). Without the helper the
#   URL is accepted during eval and then fails at transport — a failure far from
#   its cause. The helper must exist wherever flake inputs are fetched.
{
  config,
  lib,
  inputs,
  ...
}: let
  cfg = config.services.gitlawb-client;
in {
  # The `programs.gitlawb` option is DECLARED by the gitlawb flake's own NixOS
  # module. Import it here so this feature is self-contained: a host opts in with
  # one `services.gitlawb-client.enable = true;` and does not additionally have
  # to know that it must import inputs.gitlawb.nixosModule. Importing the
  # declaring module is inert on its own — it only declares options; nothing
  # activates until programs.gitlawb.enable is set in the config block below.
  imports = [inputs.gitlawb.nixosModule];

  options.services.gitlawb-client = {
    enable = lib.mkEnableOption ''
      the Gitlawb client: the `gl` CLI and the `git-remote-gitlawb` helper that
      makes `gitlawb://` URLs resolvable by plain git, and therefore by Lix
      flake inputs. Enable on any host that fetches gitlawb:// flake inputs
      (notably the cluster build host)
    '';

    nodeUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://10.1.1.140:7545";
      example = "http://10.1.1.140:7545";
      description = ''
        Base URL of the Gitlawb node this host talks to.

        Required in practice, and the exact check `gl doctor` reports as failing
        when absent: with no GITLAWB_NODE in the environment,
        `git-remote-gitlawb` silently falls back to http://127.0.0.1:7545 and
        every fetch times out against a port nothing is listening on.

        Defaults to sentry, which is the host running services.gitlawb-node.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Installs `gl`, `git-remote-gitlawb`, and `gitlawb-node` from a single
    # prebuilt release derivation, and exports GIT_LAWB_HELPER.
    programs.gitlawb.enable = true;

    # Exported to interactive shells and to units that inherit the session
    # environment, so `git clone gitlawb://…` and Lix's own git subprocesses
    # agree on which node to contact.
    environment.sessionVariables.GITLAWB_NODE = cfg.nodeUrl;
  };
}

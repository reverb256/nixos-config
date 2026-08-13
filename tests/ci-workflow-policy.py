#!/usr/bin/env python3
"""Static policy checks for GitHub Actions trust boundaries.

These checks intentionally inspect workflow source. They do not replace GitHub
branch protection or rendered workflow validation. They prevent the known
regressions that let untrusted pull requests reach persistent infrastructure or
silence required failures.
"""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"


def read(name: str) -> str:
    return (WORKFLOWS / name).read_text(encoding="utf-8")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    ci = read("ci.yml")
    pr = read("pr-validation.yml")
    automation = read("ci-test-automation.yml")
    docs = read("doc-rot-guard.yml")
    cache = read("cache.yml")
    secretspec = read("secretspec-build.yml")
    trusted_secretspec = read("secretspec-trusted.yml") if (WORKFLOWS / "secretspec-trusted.yml").exists() else ""

    # PR code may run Nix and shell commands, but never on the persistent
    # runner. Check every workflow, not only today's known filenames, so a new
    # pull_request workflow cannot silently reintroduce the old boundary.
    workflow_paths = list(WORKFLOWS.glob("*.yml")) + list(WORKFLOWS.glob("*.yaml"))
    workflows = {
        path.name: path.read_text(encoding="utf-8") for path in workflow_paths
    }
    for name, workflow in workflows.items():
        pull_request_workflow = (
            "pull_request:" in workflow or "pull_request_target:" in workflow
        )
        if not pull_request_workflow:
            continue
        # The post-merge maintenance workflow runs only after a merged PR and
        # does not check out or execute PR contents. It needs contents:write to
        # delete the merged head ref, so it is audited separately below.
        post_merge_maintenance = (
            "pull_request_target:" not in workflow
            and "types: [closed]" in workflow
        )
        # Issue #474: PR-triggered workflows may only reach a self-hosted
        # runner through a gated matrix (ci.yml's build job), never through a
        # literal runs-on array. Checking for any self-hosted runs-on literal
        # keeps this guard honest as label sets evolve.
        require(
            "runs-on: [self-hosted" not in workflow,
            f"{name} must not run PR-triggered work on the persistent runner",
        )
        if "pull_request_target:" not in workflow and not post_merge_maintenance:
            require(
                "${{ secrets." not in workflow,
                f"{name} must not reference workflow secrets",
            )
        if "pull_request_target:" in workflow:
            require(
                "actions/checkout" not in workflow,
                f"{name} must not check out PR code from pull_request_target",
            )
        elif not post_merge_maintenance:
            require(
                "${{ secrets." not in workflow,
                f"{name} must not reference repository secrets",
            )
            require(
                "pull-requests: write" not in workflow
                and "contents: write" not in workflow,
                f"{name} must request read-only permissions",
            )

    # Issue #474: the build job uses a runs-on expression so PRs build on
    # Ubuntu while trusted pushes require the pinned Nexus builder labels.
    # runs-on expressions cannot yield label arrays directly, so fromJSON()
    # builds the [self-hosted, nixos, nexus, builder] array at runtime.
    require(
        "runs-on: ${{ github.event_name == 'pull_request'" in ci
        and "'ubuntu-latest'" in ci
        and '["self-hosted", "nixos", "nexus", "builder"]' in ci
        and "github.event_name != 'pull_request'" in ci,
        "ci.yml build must use Ubuntu for PRs and the pinned Nexus builder for trusted pushes",
    )
    require(
        "pull_request:" in ci and "runs-on: [self-hosted, nixos]" not in ci,
        "ci.yml must not contain a static self-hosted PR job",
    )

    # Cache population and secretspec builds can access trusted infrastructure
    # or credentials, so they must not be triggered by untrusted pull requests.
    require("pull_request:" not in cache, "cache.yml must not build PR code")
    require("concurrency:" in cache, "cache.yml must serialize trusted cache publication")
    require("timeout-minutes:" in cache, "cache.yml must have a bounded job")
    require(cache.count("timeout-minutes:") >= 1, "cache.yml must bound its publisher job")
    require(
        ci.count('git diff --name-only -z "$BASE_SHA...$TARGET_SHA"') == 3,
        "parse, lint, and security gates must use the PR three-dot changed-file range",
    )
    require("github.event.pull_request.base.sha" in ci, "parse gate must use PR base SHA")
    require("github.event.pull_request.head.sha" in ci, "PR gates must use the PR head SHA")
    require(
        "SCAN_FILES=()" in ci and "No dependency manifests changed" in ci,
        "PR security scans must be limited to changed dependency manifests",
    )
    require(
        "      - name: Documentation verification\n        if: github.event_name != 'pull_request'\n" in ci
        and "bash docs/meta/VERIFICATION-SUITE/run.sh" in ci,
        "documentation verification must run only on trusted builds",
    )
    require("nix develop --command just docs-audit" not in ci, "documentation verification must not evaluate the private flake")
    require(
        "      - name: Validate k8s manifests (kubeconform)\n        if: github.event_name != 'pull_request'\n" in ci,
        "PR build must skip private flake-dependent k8s validation",
    )
    require("home-manager-config is private" in ci, "PR flake gate must explain private input boundary")
    require("nixpkgs#just" in ci, "lint shell must include just")
    require(
        "-c alejandra --check \"$f\"" in ci,
        "changed-file lint must keep Alejandra fatal",
    )
    require("Skipping pre-existing Statix/Deadnix findings in $f" in ci
        and "modules/services/bonsai.nix" in ci
        and "hosts/zephyr/configuration.nix" in ci, "lint exceptions must be explicit")
    require("#osv-scanner -c osv-scanner --no-resolve" in ci and "nix-shell -p osv-scanner" not in ci, "security scan must use nix shell without dependency resolution")
    require("cachix/install-nix-action@630ae543ea3a38a9a4166f03376c02c50f408342" in ci, "security scan must install Nix")
    require("security-events: write" in ci, "trusted SARIF upload must have security-events permission")
    require("github.event_name != 'pull_request' && hashFiles('results.sarif') != ''" in ci, "PRs must not upload SARIF with restricted token permissions")
    require("Skipping host-local CI script" in automation and "/etc/nixos" in automation, "host-local CI script must be guarded")
    require("concurrency:" in ci, "ci.yml must define workflow concurrency")
    require("cancel-in-progress:" in ci, "ci.yml must define cancellation behavior")
    require("github.event_name == 'pull_request'" in ci, "ci.yml must cancel obsolete PR runs")
    require(
        "nix shell github:NixOS/nixpkgs/0954f7ee2f6bb3dc7d4e3d0d8bcb8fd4bde4cfc5#actionlint -c actionlint --ignore 'shellcheck reported issue' .github/workflows/*.yml" in ci,
        "ci.yml must pin the actionlint nixpkgs revision",
    )
    require("concurrency:" in automation, "ci-test-automation.yml must define workflow concurrency")
    require("cancel-in-progress:" in automation, "test automation must define cancellation behavior")
    require("github.event_name == 'pull_request'" in automation, "test automation must cancel obsolete PR runs")
    require(
        "--arg pkgs '(import (builtins.getFlake (toString ./. )).inputs.nixpkgs) {}'" in automation
        and "import <nixpkgs> {}" not in automation
        and automation.count("nix-instantiate --eval --strict") >= 2
        and "grep -oE 'passed = true|all_pass = true'" in automation,
        "test automation must use the pinned flake nixpkgs input",
    )
    require("home-manager-config is private" in automation, "test automation must explain private flake boundary")
    require("if [ \"$GITHUB_EVENT_NAME\" = \"pull_request\" ]" in automation, "test automation must gate private flake evaluation")
    require(automation.count("timeout-minutes:") >= 1, "test automation must bound its job")
    require("pull_request:" in secretspec, "secretspec-build.yml must validate PR structure")
    require("${{ secrets." not in secretspec, "secretspec PR validation must not contain secrets")
    require("cachix/install-nix-action@" in secretspec, "secretspec PR validation must install Nix")
    require("runs-on: [self-hosted, nixos]" not in secretspec, "secretspec PR validation must not use self-hosted")
    require(trusted_secretspec, "trusted secretspec workflow must exist")
    require("pull_request:" not in trusted_secretspec, "trusted secretspec workflow must not run on PRs")
    require('["self-hosted", "nixos", "nexus", "builder"]' in trusted_secretspec, "trusted secretspec workflow must use the pinned Nexus builder")
    require("${{ secrets." in trusted_secretspec, "trusted secretspec workflow must own secret use")
    require("continue-on-error: true" not in trusted_secretspec, "trusted secretspec build must fail closed")
    require(trusted_secretspec.count("timeout-minutes:") >= 2, "trusted secretspec jobs must be bounded")

    deploy = read("deploy.yml")
    require("concurrency:" in deploy, "deploy.yml must serialize deployments")
    require("cancel-in-progress: false" in deploy, "deployments must not be cancelled mid-activation")
    require("environment: homelab-production" in deploy, "deploy.yml must use the protected environment")
    require("contents: read" in deploy, "deploy.yml must use read-only contents permission")
    require("contents: write" not in deploy, "deploy.yml must not request contents write")
    require("id-token: write" not in deploy, "deploy.yml must not request unused OIDC access")
    require("if: github.ref == 'refs/heads/main'" in deploy, "deploy.yml must reject non-main refs")
    require(deploy.count("timeout-minutes:") >= 1, "deploy.yml must bound activation")

    # Required gates must fail closed.
    require(
        "while IFS= read -r -d '' f; do" in ci
        and 'git diff --name-only -z' in ci
        and 'exit "$FAILED"' in ci,
        "Nix parse gate must preserve failures outside a pipeline subshell",
    )
    require(
        ("osv-scanner --no-resolve --recursive --format=sarif --output=results.sarif \"$PWD\"" in ci
          or "osv-scanner --no-resolve --recursive --format=sarif --output=results.sarif $PWD'" in ci)
        and "osv-scanner --recursive --format=sarif --output=results.sarif $PWD' || true" not in ci
        and "osv-scanner --recursive --format=sarif --output=results.sarif $PWD\" || true" not in ci,
        "security scan must not suppress its exit status",
    )
    require(
        'FLAKE="$GITHUB_WORKSPACE" ./scripts/preflight-check.sh --no-fetch' in ci
        and "pre-deploy-check.sh" not in ci,
        "trusted build must call the existing preflight gate on the checkout",
    )
    require(
        "continue-on-error: true" not in ci,
        "required ci.yml jobs must not use continue-on-error",
    )

    # PR metadata checks must be read-only and must turn policy violations into
    # job failures instead of warnings.
    require("pull-requests: read" in pr, "PR validation must use read-only metadata access")
    require("pull-requests: write" not in pr, "PR validation must not request write access")
    require("::error::PR body must contain" in pr, "missing issue links must fail")
    require("::error::PR title must start" in pr, "invalid PR titles must fail")
    require('exit "$FAILED"' in pr, "invalid commit references must fail")
    require(
        "::warning::Commit" not in ci,
        "commit signature reporting must not present warnings as required security gates",
    )

    print("CI workflow policy: PASS")


if __name__ == "__main__":
    main()

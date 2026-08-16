#!/usr/bin/env python3
"""Static policy checks for GitHub Actions trust boundaries.

These checks intentionally inspect workflow source. They do not replace GitHub
branch protection or rendered workflow validation. They prevent the known
regressions that let untrusted pull requests access secrets, mutate the
repository, or deploy to the cluster.

Architecture (2026-08-13 onward): ALL jobs run on the self-hosted runner.
GitHub-hosted runners are retired. The trust boundary is NOT runner placement
(it is all self-hosted) — it is what PR-triggered workflows can DO:
  - No access to repository secrets (pull_request_target is exempt — it runs
    in base branch context and never checks out PR code).
  - No deployment (only workflow_dispatch + main ref).
  - No mutation of PR contents or repository state from pull_request.
  - Read-only contents permission unless explicitly allowlisted.
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

    # -------------------------------------------------------------------------
    # Global: classify every workflow and enforce PR boundaries
    # -------------------------------------------------------------------------
    workflow_paths = list(WORKFLOWS.glob("*.yml")) + list(WORKFLOWS.glob("*.yaml"))
    workflows = {
        path.name: path.read_text(encoding="utf-8") for path in workflow_paths
    }

    # Workflows that need contents:write or pull-requests:write. These are
    # the ONLY workflows permitted to mutate anything from a PR trigger.
    WRITE_PERMISSION_ALLOWLIST = {
        "auto-delete-head-branches.yml":  "deletes merged head ref (post-merge only)",
        "dependabot-auto-merge.yml":      "enables auto-merge for dependabot (pull_request_target)",
    }

    for name, workflow in workflows.items():
        is_pr = "pull_request:" in workflow
        is_pr_target = "pull_request_target:" in workflow
        if not is_pr and not is_pr_target:
            continue

        # pull_request_target runs in base branch context — trusted.
        if is_pr_target:
            require(
                "actions/checkout" not in workflow,
                f"{name} must not check out PR code from pull_request_target",
            )
            continue

        # From here: pull_request workflows (untrusted PR code could run).

        # No secrets for pull_request workflows.
        require(
            "${{ secrets." not in workflow,
            f"{name} must not reference repository secrets",
        )

        # Write permissions only for allowlisted workflows.
        if name not in WRITE_PERMISSION_ALLOWLIST:
            require(
                "pull-requests: write" not in workflow
                and "contents: write" not in workflow,
                f"{name} must request read-only permissions",
            )

        # Deployment is never allowed from pull_request.
        require(
            "environment: homelab-production" not in workflow,
            f"{name} must not deploy from pull_request",
        )

    # -------------------------------------------------------------------------
    # ci.yml — the trusted CI workflow
    # -------------------------------------------------------------------------
    require("pull_request:" in ci, "ci.yml must trigger on pull_request")
    require(
        "runs-on: [self-hosted, nixos]" in ci
        or "runs-on: [self-hosted, nixos, nexus, builder]" in ci,
        "ci.yml jobs must run on self-hosted",
    )
    require("concurrency:" in ci, "ci.yml must define workflow concurrency")
    require("cancel-in-progress:" in ci, "ci.yml must define cancellation behavior")
    require(
        "github.event_name == 'pull_request'" in ci,
        "ci.yml must cancel obsolete PR runs",
    )

    # Build uses the pinned Nexus builder.
    require(
        "runs-on: [self-hosted, nixos, nexus, builder]" in ci,
        "ci.yml build must use the pinned Nexus builder",
    )

    # Parse/lint/security gates use the three-dot changed-file range.
    require(
        ci.count('git diff --name-only -z "$BASE_SHA...$TARGET_SHA"') == 3,
        "parse, lint, and security gates must use the PR three-dot changed-file range",
    )
    require("github.event.pull_request.base.sha" in ci, "parse gate must use PR base SHA")
    require("github.event.pull_request.head.sha" in ci, "PR gates must use the PR head SHA")

    # Test suite must use the locked flake nixpkgs, not the runner channel.
    require("import <nixpkgs> {}" not in ci, "ci.yml test suite must not use the runner channel nixpkgs")
    require("(import (builtins.getFlake (toString ./. )).inputs.nixpkgs) {}" in ci, "ci.yml test suite must use the locked flake nixpkgs input")

    # Security scan limited to changed dependency manifests.
    require(
        "SCAN_FILES=()" in ci and "No dependency manifests changed" in ci,
        "PR security scans must be limited to changed dependency manifests",
    )

    # Private flake gates.
    require(
        "      - name: Documentation verification\n        if: github.event_name != 'pull_request'\n" in ci
        and "bash docs/meta/VERIFICATION-SUITE/run.sh" in ci,
        "documentation verification must run only on trusted builds",
    )
    require("nix develop --command just docs-audit" not in ci, "documentation verification stays in doc-rot-guard.yml (single owner)")
    require(
        "      - name: Validate k8s manifests (kubeconform)\n        if: github.event_name != 'pull_request'\n" in ci,
        "PR build keeps heavy k8s manifest validation trusted-only",
    )
    require("home-manager-config is private" not in ci, "flake check must not be gated behind a stale private-input rationale")
    require("nix flake check --no-build" in ci, "quick-check must run the full flake check on PRs and pushes")

    # Lint shell derives its nixpkgs rev from flake.lock (no hardcoded rev).
    require(
        "0954f7ee2f6bb3dc7d4e3d0d8bcb8fd4bde4cfc5" not in ci,
        "toolchain nixpkgs rev must not be hardcoded",
    )
    require(
        "github:NixOS/nixpkgs/$NIXPKGS_REV#alejandra" in ci,
        "lint shell must derive alejandra from the locked nixpkgs rev",
    )
    require(
        "github:NixOS/nixpkgs/$NIXPKGS_REV#just" in ci,
        "lint shell must derive just from the locked nixpkgs rev",
    )
    require(
        "-c alejandra --check \"$f\"" in ci,
        "changed-file lint must keep Alejandra fatal",
    )
    require("Skipping pre-existing Statix/Deadnix findings in $f" in ci
        and "modules/services/bonsai.nix" in ci
        and "hosts/zephyr/configuration.nix" in ci, "lint exceptions must be explicit")

    # Security scan tooling.
    require("osv-scanner --no-resolve" in ci and "nix-shell -p osv-scanner" not in ci, "security scan must use nix shell without dependency resolution")
    require("github:NixOS/nixpkgs/$NIXPKGS_REV#osv-scanner" in ci, "security scan must derive osv-scanner from the locked nixpkgs rev")
    require("security-events: write" in ci, "trusted SARIF upload must have security-events permission")
    require("github.event_name != 'pull_request' && hashFiles('results.sarif') != ''" in ci, "PRs must not upload SARIF with restricted token permissions")

    # Actionlint derives its nixpkgs rev from flake.lock and runs shellcheck
    # (scoped disables live in .github/actionlint.yaml — no blanket --ignore).
    require(
        'nix shell "github:NixOS/nixpkgs/$NIXPKGS_REV#actionlint" -c actionlint .github/workflows/*.yml' in ci,
        "ci.yml must derive actionlint from the locked nixpkgs rev",
    )
    require(
        "--ignore 'shellcheck reported issue'" not in ci,
        "ci.yml must not blanket-suppress shellcheck findings",
    )

    # Preflight gate on trusted build.
    require(
        'FLAKE="$GITHUB_WORKSPACE" ./scripts/preflight-check.sh --no-fetch' in ci
        and "pre-deploy-check.sh" not in ci,
        "trusted build must call the existing preflight gate on the checkout",
    )
    require(
        "continue-on-error: true" not in ci,
        "required ci.yml jobs must not use continue-on-error",
    )
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
    # Commit signature reporting is advisory (notice), not a security gate.
    require(
        "::warning::Commit" not in ci,
        "commit signature reporting must not present warnings as required security gates",
    )

    # -------------------------------------------------------------------------
    # pr-validation.yml
    # -------------------------------------------------------------------------
    require("pull-requests: read" in pr, "PR validation must use read-only metadata access")
    require("pull-requests: write" not in pr, "PR validation must not request write access")
    require("::error::PR body must contain" in pr, "missing issue links must fail")
    require("::error::PR title must start" in pr, "invalid PR titles must fail")
    require('exit "$FAILED"' in pr, "invalid commit references must fail")
    require('"prod"' not in pr, "PR validation must not allow the removed prod branch")

    # -------------------------------------------------------------------------
    # ci-test-automation.yml
    # -------------------------------------------------------------------------
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
    require("home-manager-config is private" not in automation, "test automation must not gate flake eval behind a stale private-input rationale")
    require("nix flake check --no-build" in automation, "test automation must run the full flake check unconditionally")
    require(automation.count("timeout-minutes:") >= 1, "test automation must bound its job")
    require("Skipping host-local CI script" in automation and "/etc/nixos" in automation, "host-local CI script must be guarded")

    # -------------------------------------------------------------------------
    # doc-rot-guard.yml
    # -------------------------------------------------------------------------
    # Read-only, no secrets — runs staleness checks only.
    require("contents: read" in docs, "doc-rot-guard must use read-only contents")

    # -------------------------------------------------------------------------
    # cache.yml — trusted only, never PRs
    # -------------------------------------------------------------------------
    require("pull_request:" not in cache, "cache.yml must not build PR code")
    require("concurrency:" in cache, "cache.yml must serialize trusted cache publication")
    require("timeout-minutes:" in cache, "cache.yml must have a bounded job")
    require(cache.count("timeout-minutes:") >= 1, "cache.yml must bound its publisher job")

    # -------------------------------------------------------------------------
    # secretspec-build.yml
    # -------------------------------------------------------------------------
    require("pull_request:" in secretspec, "secretspec-build.yml must validate PR structure")
    require("${{ secrets." not in secretspec, "secretspec PR validation must not contain secrets")
    require("nix-instantiate --parse" in secretspec, "secretspec PR validation must parse Nix files")
    require(trusted_secretspec, "trusted secretspec workflow must exist")
    require("pull_request:" not in trusted_secretspec, "trusted secretspec workflow must not run on PRs")
    require('["self-hosted", "nixos", "nexus", "builder"]' in trusted_secretspec, "trusted secretspec workflow must use the pinned Nexus builder")
    require("${{ secrets." in trusted_secretspec, "trusted secretspec workflow must own secret use")
    require("continue-on-error: true" not in trusted_secretspec, "trusted secretspec build must fail closed")
    require(trusted_secretspec.count("timeout-minutes:") >= 2, "trusted secretspec jobs must be bounded")

    # -------------------------------------------------------------------------
    # deploy.yml — workflow_dispatch only, main ref only
    # -------------------------------------------------------------------------
    deploy = read("deploy.yml")
    require("concurrency:" in deploy, "deploy.yml must serialize deployments")
    require("cancel-in-progress: false" in deploy, "deployments must not be cancelled mid-activation")
    require("environment: homelab-production" in deploy, "deploy.yml must use the protected environment")
    require("contents: read" in deploy, "deploy.yml must use read-only contents permission")
    require("contents: write" not in deploy, "deploy.yml must not request contents write")
    require("id-token: write" not in deploy, "deploy.yml must not request unused OIDC access")
    require("if: github.ref == 'refs/heads/main'" in deploy, "deploy.yml must reject non-main refs")
    require(
        'FLAKE="$GITHUB_WORKSPACE" ./scripts/preflight-check.sh' in deploy,
        "deploy must gate on the checked-out ref via preflight",
    )
    require(
        'cd "$GITHUB_WORKSPACE"' in deploy,
        "deploy must build and activate from the checked-out ref, not /etc/nixos",
    )
    require(
        'ssh zephyr "uptime"' in deploy,
        "deploy health check must probe zephyr, not the runner host",
    )
    require(deploy.count("timeout-minutes:") >= 1, "deploy.yml must bound activation")

    print("CI workflow policy: PASS")


if __name__ == "__main__":
    main()

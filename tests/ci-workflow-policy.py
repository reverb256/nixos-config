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
        require(
            "runs-on: [self-hosted, nixos]" not in workflow,
            f"{name} must not run PR-triggered work on the persistent runner",
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

    require(
        "runs-on: ${{ github.event_name == 'pull_request' && 'ubuntu-latest' || 'self-hosted' }}"
        in ci,
        "ci.yml must use Ubuntu for PRs and self-hosted only for trusted pushes",
    )
    require(
        "pull_request:" in ci and "runs-on: [self-hosted, nixos]" not in ci,
        "ci.yml must not contain a static self-hosted PR job",
    )

    # Cache population and secretspec builds can access trusted infrastructure
    # or credentials, so they must not be triggered by untrusted pull requests.
    require("pull_request:" not in cache, "cache.yml must not build PR code")
    require("pull_request:" not in secretspec, "secretspec-build.yml must not run PR code")

    # Required gates must fail closed.
    require(
        'done < <(find . -name "*.nix" -not -path "./.git/*")' in ci,
        "Nix parse gate must preserve failures outside a pipeline subshell",
    )
    require(
        "osv-scanner --recursive --format=sarif --output=results.sarif $PWD'" in ci
        and "osv-scanner --recursive --format=sarif --output=results.sarif $PWD' || true" not in ci,
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

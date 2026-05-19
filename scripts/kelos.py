#!/usr/bin/env python3
"""Kelos task dispatcher with context bridge integration.

Creates Kelos Task CRDs from dispatch tasks and writes initial context
for inter-agent state passing.

Usage:
    python kelos.py dispatch --issue 42 --type bug --repo nixos-config
    python kelos.py status --task 42
    python kelos.py list
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

# Configuration
CONTEXT_DIR = os.environ.get("KELOS_CONTEXT_DIR", "/data/agents/context")
STATE_DIR = os.environ.get("KELOS_STATE_DIR", "/data/agents/state")
TASKS_FILE = os.path.join(STATE_DIR, "tasks.json")
KELOS_NAMESPACE = os.environ.get("KELOS_NAMESPACE", "kelos-system")

# Prompt templates by issue type (mirrors kelos.nix)
PROMPT_TEMPLATES = {
    "bug": """GitHub issue #{issue}: {title}

Description:
{body}

This is a BUG fix. Focus on:
- Identifying and fixing the root cause
- Adding tests to verify the fix and prevent regression
- Verifying the fix works as expected

Implement the required changes, push the branch, and open a PR against main.
Branch: kelos-task-{issue}
Every commit message must include #{issue}.
The workspace at /workspace/repo is writable — work directly there.""",

    "enhancement": """GitHub issue #{issue}: {title}

Description:
{body}

This is an ENHANCEMENT. Focus on:
- Clean implementation following existing patterns
- Adding documentation for new functionality
- Considering edge cases and error handling

Implement the required changes, push the branch, and open a PR against main.
Branch: kelos-task-{issue}
Every commit message must include #{issue}.
The workspace at /workspace/repo is writable — work directly there.""",

    "security": """GitHub issue #{issue}: {title}

Description:
{body}

This is a SECURITY issue. Focus on:
- Hardening the code against vulnerabilities
- Auditing for potential security issues
- Adding security-focused tests

Implement the required changes, push the branch, and open a PR against main.
Branch: kelos-task-{issue}
Every commit message must include #{issue}.
The workspace at /workspace/repo is writable — work directly there.""",

    "refactor": """GitHub issue #{issue}: {title}

Description:
{body}

This is a REFACTOR. Focus on:
- Improving code structure and maintainability
- Maintaining backward compatibility
- Preserving existing behavior while improving internals

Implement the required changes, push the branch, and open a PR against main.
Branch: kelos-task-{issue}
Every commit message must include #{issue}.
The workspace at /workspace/repo is writable — work directly there.""",

    "cleanup": """GitHub issue #{issue}: {title}

Description:
{body}

This is a CLEANUP task. Focus on:
- Making minimal, targeted changes
- Not breaking existing behavior
- Removing dead code, fixing formatting, or simplifying logic

Implement the required changes, push the branch, and open a PR against main.
Branch: kelos-task-{issue}
Every commit message must include #{issue}.
The workspace at /workspace/repo is writable — work directly there.""",
}


def ensure_context_dir(issue_number):
    """Ensure context directory exists for an issue."""
    ctxt_dir = os.path.join(CONTEXT_DIR, str(issue_number))
    os.makedirs(ctxt_dir, exist_ok=True)
    return ctxt_dir


def write_initial_context(issue_number, issue_type, title="", body=""):
    """Write initial context when dispatching a Kelos task.

    Creates analysis.md with issue details and initializes results.json.
    """
    ctxt_dir = ensure_context_dir(issue_number)

    # Write analysis.md with issue details
    analysis_path = os.path.join(ctxt_dir, "analysis.md")
    if not os.path.exists(analysis_path) or os.path.getsize(analysis_path) == 0:
        with open(analysis_path, "w") as f:
            f.write(f"# Analysis for #{issue_number}\n\n")
            f.write(f"## Issue: {title}\n\n")
            f.write(f"## Type: {issue_type}\n\n")
            f.write(f"## Description\n\n{body}\n\n")
            f.write(f"## Investigation\n\n_Pending analysis by agent._\n")

    # Write/update results.json
    results_path = os.path.join(ctxt_dir, "results.json")
    results = {
        "stage": "analysis",
        "agent": "kelos",
        "issue": issue_number,
        "branch": f"kelos-task-{issue_number}",
        "commit": None,
        "pr": None,
        "status": "dispatched",
        "blocker": None,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

    # Merge with existing results if present
    if os.path.exists(results_path):
        with open(results_path, "r") as f:
            existing = json.load(f)
        results.update(existing)
        results["status"] = "dispatched"
        results["timestamp"] = datetime.now(timezone.utc).isoformat()

    with open(results_path, "w") as f:
        json.dump(results, f, indent=2)

    return ctxt_dir


def generate_task_crd(issue_number, issue_type, repo, title="", body=""):
    """Generate a Kelos Task CRD YAML.

    Returns the YAML manifest for kubectl apply.
    """
    prompt = PROMPT_TEMPLATES.get(issue_type, PROMPT_TEMPLATES["enhancement"])
    prompt = prompt.format(issue=issue_number, title=title or f"Issue #{issue_number}", body=body or "")

    task = {
        "apiVersion": "kelos.dev/v1alpha1",
        "kind": "Task",
        "metadata": {
            "name": f"task-{issue_number}",
            "namespace": KELOS_NAMESPACE,
            "labels": {
                "app.kubernetes.io/managed-by": "kelos",
                "app.kubernetes.io/part-of": "agent-dispatch",
                "kelos.dev/issue": str(issue_number),
                "kelos.dev/type": issue_type,
            },
        },
        "spec": {
            "type": "opencode",
            "workspaceRef": {"name": f"workspace-{repo}"},
            "agentConfigRef": {"name": "cluster-coder"},
            "branch": f"kelos-task-{issue_number}",
            "promptTemplate": prompt,
            "ttlSecondsAfterFinished": 900,
        },
    }

    return task


def cmd_dispatch(args):
    """Dispatch a Kelos task with context bridge integration."""
    # Write initial context
    ctxt_dir = write_initial_context(
        args.issue,
        args.type,
        title=getattr(args, "title", ""),
        body=getattr(args, "body", ""),
    )

    # Generate Task CRD
    task_crd = generate_task_crd(
        args.issue,
        args.type,
        args.repo,
        title=getattr(args, "title", ""),
        body=getattr(args, "body", ""),
    )

    # Output the CRD
    if args.dry_run:
        print(json.dumps(task_crd, indent=2))
    else:
        # In production, this would use kubectl to apply the CRD
        crd_path = os.path.join(ctxt_dir, "task-crd.json")
        with open(crd_path, "w") as f:
            json.dump(task_crd, f, indent=2)
        print(f"Task CRD generated for issue #{args.issue}")
        print(f"  Context: {ctxt_dir}")
        print(f"  CRD: {crd_path}")
        print(f"  Branch: kelos-task-{args.issue}")

    return task_crd


def cmd_status(args):
    """Show status of a Kelos task."""
    ctxt_dir = os.path.join(CONTEXT_DIR, str(args.issue))

    if not os.path.exists(ctxt_dir):
        print(f"No context found for issue #{args.issue}")
        sys.exit(1)

    print(f"=== Context for #{args.issue} ===")
    for f in sorted(os.listdir(ctxt_dir)):
        filepath = os.path.join(ctxt_dir, f)
        if os.path.isfile(filepath):
            size = os.path.getsize(filepath)
            print(f"\n--- {f} ({size} bytes) ---")
            if f.endswith(".json"):
                with open(filepath, "r") as fh:
                    print(json.dumps(json.load(fh), indent=2))
            else:
                # Show first 500 chars of markdown files
                with open(filepath, "r") as fh:
                    content = fh.read()
                    print(content[:500])
                    if len(content) > 500:
                        print("... (truncated)")


def cmd_list(args):
    """List all dispatched Kelos tasks."""
    if not os.path.exists(CONTEXT_DIR):
        print("No context directories found")
        return

    print(f"{'Issue':<8} {'Stage':<15} {'Agent':<10} {'Status':<12}")
    print("-" * 50)

    for entry in sorted(os.listdir(CONTEXT_DIR)):
        ctxt_dir = os.path.join(CONTEXT_DIR, entry)
        if not os.path.isdir(ctxt_dir):
            continue

        results_path = os.path.join(ctxt_dir, "results.json")
        if os.path.exists(results_path):
            with open(results_path, "r") as f:
                results = json.load(f)
            print(
                f"#{results['issue']:<7} {results['stage']:<15} "
                f"{results['agent']:<10} {results['status']:<12}"
            )
        else:
            print(f"#{entry:<7} {'unknown':<15} {'unknown':<10} {'unknown':<12}")


def main():
    parser = argparse.ArgumentParser(description="Kelos task dispatcher")
    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    # dispatch
    p_dispatch = subparsers.add_parser("dispatch", help="Dispatch a Kelos task")
    p_dispatch.add_argument("--issue", type=int, required=True, help="GitHub issue number")
    p_dispatch.add_argument("--type", choices=["bug", "enhancement", "security", "refactor", "cleanup"], required=True)
    p_dispatch.add_argument("--repo", required=True, help="Target repository")
    p_dispatch.add_argument("--title", default="", help="Issue title")
    p_dispatch.add_argument("--body", default="", help="Issue body/description")
    p_dispatch.add_argument("--dry-run", action="store_true", help="Print CRD without applying")
    p_dispatch.set_defaults(func=cmd_dispatch)

    # status
    p_status = subparsers.add_parser("status", help="Show task status")
    p_status.add_argument("--issue", type=int, required=True, help="GitHub issue number")
    p_status.set_defaults(func=cmd_status)

    # list
    p_list = subparsers.add_parser("list", help="List all tasks")
    p_list.set_defaults(func=cmd_list)

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)

    args.func(args)


if __name__ == "__main__":
    main()

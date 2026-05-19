#!/usr/bin/env python3
"""Agent dispatch system with context bridge integration.

Manages a shared task queue with claim/done/fail lifecycle.
Creates context bridge directories for inter-agent state passing.

Usage:
    python dispatch.py create --issue 42 --type bug --agent kelos
    python dispatch.py claim --task-id 42
    python dispatch.py done --task-id 42
    python dispatch.py fail --task-id 42 --reason "blocked by #41"
    python dispatch.py list
    python dispatch.py status --task-id 42
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

# Configuration
STATE_DIR = os.environ.get("DISPATCH_STATE_DIR", "/data/agents/state")
TASKS_FILE = os.path.join(STATE_DIR, "tasks.json")
CONTEXT_DIR = os.environ.get("DISPATCH_CONTEXT_DIR", "/data/agents/context")


def ensure_dirs():
    """Ensure state and context directories exist."""
    os.makedirs(STATE_DIR, exist_ok=True)
    os.makedirs(CONTEXT_DIR, exist_ok=True)


def load_tasks():
    """Load tasks from the shared state file."""
    if not os.path.exists(TASKS_FILE):
        return {"tasks": [], "next_id": 1}
    with open(TASKS_FILE, "r") as f:
        return json.load(f)


def save_tasks(data):
    """Save tasks to the shared state file."""
    with open(TASKS_FILE, "w") as f:
        json.dump(data, f, indent=2)


def create_context_dir(issue_number, initial_data=None):
    """Create context bridge directory for an issue.

    Creates the standard context structure:
    - analysis.md (empty, ready for agent to fill)
    - plan.md (empty)
    - review.md (empty)
    - results.json (with initial structured data)
    - handoff.md (empty)
    """
    ctxt_dir = os.path.join(CONTEXT_DIR, str(issue_number))
    os.makedirs(ctxt_dir, exist_ok=True)

    # Create empty markdown templates
    for filename in ["analysis.md", "plan.md", "review.md", "handoff.md"]:
        filepath = os.path.join(ctxt_dir, filename)
        if not os.path.exists(filepath):
            with open(filepath, "w") as f:
                f.write(f"# {filename.replace('.md', '').title()} for #{issue_number}\n\n")

    # Create initial results.json
    results_path = os.path.join(ctxt_dir, "results.json")
    if not os.path.exists(results_path):
        results = {
            "stage": "analysis",
            "agent": "unknown",
            "issue": issue_number,
            "branch": None,
            "commit": None,
            "pr": None,
            "status": "pending",
            "blocker": None,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        if initial_data:
            results.update(initial_data)
        with open(results_path, "w") as f:
            json.dump(results, f, indent=2)

    return ctxt_dir


def cmd_create(args):
    """Create a new dispatch task with context bridge directory."""
    ensure_dirs()
    data = load_tasks()

    task_id = data["next_id"]
    task = {
        "id": task_id,
        "issue": args.issue,
        "type": args.type,
        "agent": args.agent,
        "status": "pending",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "claimed_at": None,
        "completed_at": None,
        "claimed_by": None,
        "result": None,
    }

    data["tasks"].append(task)
    data["next_id"] = task_id + 1
    save_tasks(data)

    # Create context bridge directory
    ctxt_dir = create_context_dir(args.issue, {
        "agent": args.agent,
        "issue": args.issue,
    })

    print(f"Task #{task_id} created for issue #{args.issue}")
    print(f"  Type: {args.type}")
    print(f"  Agent: {args.agent}")
    print(f"  Context: {ctxt_dir}")
    return task_id


def cmd_claim(args):
    """Claim a task for processing."""
    ensure_dirs()
    data = load_tasks()

    for task in data["tasks"]:
        if task["id"] == args.task_id and task["status"] == "pending":
            task["status"] = "claimed"
            task["claimed_at"] = datetime.now(timezone.utc).isoformat()
            task["claimed_by"] = args.agent
            save_tasks(data)

            # Update context with claim info
            ctxt_dir = os.path.join(CONTEXT_DIR, str(task["issue"]))
            if os.path.exists(ctxt_dir):
                results_path = os.path.join(ctxt_dir, "results.json")
                if os.path.exists(results_path):
                    with open(results_path, "r") as f:
                        results = json.load(f)
                    results["agent"] = args.agent
                    results["status"] = "in_progress"
                    results["timestamp"] = datetime.now(timezone.utc).isoformat()
                    with open(results_path, "w") as f:
                        json.dump(results, f, indent=2)

            print(f"Task #{args.task_id} claimed by {args.agent}")
            return

    print(f"Task #{args.task_id} not found or already claimed")
    sys.exit(1)


def cmd_done(args):
    """Mark a task as completed."""
    ensure_dirs()
    data = load_tasks()

    for task in data["tasks"]:
        if task["id"] == args.task_id and task["status"] == "claimed":
            task["status"] = "done"
            task["completed_at"] = datetime.now(timezone.utc).isoformat()
            task["result"] = args.result
            save_tasks(data)

            # Update context with completion info
            ctxt_dir = os.path.join(CONTEXT_DIR, str(task["issue"]))
            if os.path.exists(ctxt_dir):
                results_path = os.path.join(ctxt_dir, "results.json")
                if os.path.exists(results_path):
                    with open(results_path, "r") as f:
                        results = json.load(f)
                    results["status"] = "completed"
                    results["timestamp"] = datetime.now(timezone.utc).isoformat()
                    if args.branch:
                        results["branch"] = args.branch
                    if args.commit:
                        results["commit"] = args.commit
                    if args.pr:
                        results["pr"] = args.pr
                    with open(results_path, "w") as f:
                        json.dump(results, f, indent=2)

            print(f"Task #{args.task_id} completed")
            return

    print(f"Task #{args.task_id} not found or not claimed")
    sys.exit(1)


def cmd_fail(args):
    """Mark a task as failed."""
    ensure_dirs()
    data = load_tasks()

    for task in data["tasks"]:
        if task["id"] == args.task_id and task["status"] == "claimed":
            task["status"] = "failed"
            task["completed_at"] = datetime.now(timezone.utc).isoformat()
            task["result"] = f"Failed: {args.reason}"
            save_tasks(data)

            # Update context with failure info
            ctxt_dir = os.path.join(CONTEXT_DIR, str(task["issue"]))
            if os.path.exists(ctxt_dir):
                results_path = os.path.join(ctxt_dir, "results.json")
                if os.path.exists(results_path):
                    with open(results_path, "r") as f:
                        results = json.load(f)
                    results["status"] = "failed"
                    results["blocker"] = args.reason
                    results["timestamp"] = datetime.now(timezone.utc).isoformat()
                    with open(results_path, "w") as f:
                        json.dump(results, f, indent=2)

            print(f"Task #{args.task_id} failed: {args.reason}")
            return

    print(f"Task #{args.task_id} not found or not claimed")
    sys.exit(1)


def cmd_list(args):
    """List all tasks."""
    ensure_dirs()
    data = load_tasks()

    if not data["tasks"]:
        print("No tasks")
        return

    print(f"{'ID':<6} {'Issue':<8} {'Type':<12} {'Agent':<10} {'Status':<10}")
    print("-" * 50)
    for task in data["tasks"]:
        print(
            f"{task['id']:<6} #{task['issue']:<7} {task['type']:<12} "
            f"{task.get('claimed_by', 'unknown'):<10} {task['status']:<10}"
        )


def cmd_status(args):
    """Show status of a specific task."""
    ensure_dirs()
    data = load_tasks()

    for task in data["tasks"]:
        if task["id"] == args.task_id:
            print(json.dumps(task, indent=2))

            # Also show context if available
            ctxt_dir = os.path.join(CONTEXT_DIR, str(task["issue"]))
            if os.path.exists(ctxt_dir):
                print(f"\nContext directory: {ctxt_dir}")
                for f in sorted(os.listdir(ctxt_dir)):
                    filepath = os.path.join(ctxt_dir, f)
                    if os.path.isfile(filepath):
                        size = os.path.getsize(filepath)
                        print(f"  {f} ({size} bytes)")
            return

    print(f"Task #{args.task_id} not found")
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="Agent dispatch system")
    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    # create
    p_create = subparsers.add_parser("create", help="Create a new task")
    p_create.add_argument("--issue", type=int, required=True, help="GitHub issue number")
    p_create.add_argument("--type", choices=["bug", "enhancement", "security", "refactor", "cleanup"], required=True)
    p_create.add_argument("--agent", default="kelos", help="Target agent")
    p_create.set_defaults(func=cmd_create)

    # claim
    p_claim = subparsers.add_parser("claim", help="Claim a task")
    p_claim.add_argument("--task-id", type=int, required=True)
    p_claim.add_argument("--agent", default="kelos", help="Claiming agent")
    p_claim.set_defaults(func=cmd_claim)

    # done
    p_done = subparsers.add_parser("done", help="Mark task as done")
    p_done.add_argument("--task-id", type=int, required=True)
    p_done.add_argument("--result", default="success")
    p_done.add_argument("--branch", help="Git branch created")
    p_done.add_argument("--commit", help="Git commit hash")
    p_done.add_argument("--pr", help="PR URL")
    p_done.set_defaults(func=cmd_done)

    # fail
    p_fail = subparsers.add_parser("fail", help="Mark task as failed")
    p_fail.add_argument("--task-id", type=int, required=True)
    p_fail.add_argument("--reason", required=True, help="Failure reason")
    p_fail.set_defaults(func=cmd_fail)

    # list
    p_list = subparsers.add_parser("list", help="List all tasks")
    p_list.set_defaults(func=cmd_list)

    # status
    p_status = subparsers.add_parser("status", help="Show task status")
    p_status.add_argument("--task-id", type=int, required=True)
    p_status.set_defaults(func=cmd_status)

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)

    args.func(args)


if __name__ == "__main__":
    main()

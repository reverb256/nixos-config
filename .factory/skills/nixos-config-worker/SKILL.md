---
name: nixos-config-worker
description: Worker for NixOS configuration changes (module edits, tool configs, secrets wiring)
---

# NixOS Config Worker

NOTE: Startup and cleanup are handled by `mission-worker-base`. This skill defines the WORK PROCEDURE.

## When to Use This Skill

Features that involve editing NixOS module files (.nix), tool configuration files (JSON), wiring agenix secrets, updating .gitignore, or managing git-tracked files.

## Required Skills

None (all tools are standard bash/file editing)

## Work Procedure

1. **Read the feature description carefully** - understand exactly which files need changing
2. **Read the target files first** - understand existing structure and conventions before editing
3. **Make changes following NixOS conventions**:
   - Use `lib.mkOptionDefault` for shared module lists (NEVER direct assignment)
   - Use `lib.getExe` for single executables
   - Use `lib.makeBinPath` for PATH construction
   - 2-space indentation, trailing semicolons
   - kebab-case for filenames
4. **Validate**: Run `nix flake check` after EVERY NixOS config change
5. **Verify specific assertions**: Run the exact verification commands from the feature's `verificationSteps`
6. **Check for regressions**: Ensure existing configs still reference correct paths/models
7. **Commit**: Stage only changed files, commit with descriptive message

## Example Handoff

```json
{
  "salientSummary": "Removed junk files (cat/echo) from git, added .gitignore entries, wired 3 tool configs to read ZAI key from /run/agenix/zai-api-key env var.",
  "whatWasImplemented": "Deleted /etc/nixos/cat and /etc/nixos/echo (git rm). Added 'cat', 'echo', 'Updated API key file' to .gitignore. Updated ~/.config/crush/crush.json to read apiKey from ZAI_API_KEY env var. Updated ~/.config/opencode/opencode.json to consolidate 3 configs into 1 canonical file.",
  "whatWasLeftUndone": "",
  "verification": {
    "commandsRun": [
      { "command": "git rm cat echo", "exitCode": 0, "observation": "Removed from tracking" },
      { "command": "nix flake check", "exitCode": 0, "observation": "All checks passed" },
      { "command": "rg -l 'a304de1a9f0e46fb870d59d884b9616c' /etc/nixos/", "exitCode": 1, "observation": "No matches (key removed from tracked files)" }
    ],
    "interactiveChecks": []
  },
  "tests": { "added": [] },
  "discoveredIssues": []
}
```

## When to Return to Orchestrator

- `nix flake check` fails and the fix requires changes outside the feature scope
- Feature requires modifying files that belong to another pending feature
- Requirements are ambiguous (e.g., unclear which config file is canonical)

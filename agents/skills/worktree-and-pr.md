# Issue → worktree → PR → deploy

**Last verified:** 2026-08-16

Golden rule: **Issue → Branch/Worktree → PR → Merge → Close Issue.** No direct
pushes to `main`.

## Branch model

```
main          # integration AND production; PRs land here; deployed state = main HEAD
issue-NNN-*   # all new work, only in worktrees under /data/projects/own/
```

`/etc/nixos` on all hosts stays on `main`. Every commit message carries `(#NNN)`;
every PR body carries `Closes #NNN` or `Related to #NNN`.

## Create a worktree

```bash
just new-worktree NNN          # /data/projects/own/nixos-config-NNN from issue #NNN
cd /data/projects/own/nixos-config-NNN
# edit, validate, commit
git push origin issue-NNN-desc
gh pr create --base main --head issue-NNN-desc \
  --title "type: description (#NNN)" --body "Closes #NNN"
```

Branch names must match `issue-NNN-desc` or `(feat|fix|chore|dependabot)/desc`
(CI-enforced). Titles follow conventional commits: `type(scope): description`.

## After merge

```bash
just rm-worktree NNN           # remove worktree + delete local/remote branch
cd /etc/nixos && git pull      # refresh main
just deploy                    # ship it
```

## Cleanup hygiene

```bash
git worktree remove /data/projects/own/<repo>-NNN && git branch -d issue-NNN-desc
```

Push to `origin` (GitHub) for all-node visibility — the bare/central remote is
for the deploy sync path, not feature branches.

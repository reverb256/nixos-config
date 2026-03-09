---
name: require-deployment-success
enabled: true
event: bash
pattern: (nixos-rebuild|colmena.*apply|just deploy|just nexus|just forge|just sentry)
severity: block
message: |
  # 🚨 DEPLOYMENT ERROR REPORTING HOOK

  %OUTPUT%

  ---
  **If deployment succeeded**: You may proceed.

  **If deployment failed**: You MUST:
  1. Read the error output carefully
  2. Identify the root cause
  3. Fix the issue before attempting another deployment
  4. Verify the fix addresses the actual problem

  **Common fixes:**
  - `sudo: A terminal is required` → Set up passwordless sudo on the target node
  - `attribute 'imports' already defined` → Fix duplicate imports in configuration
  - Fish config errors → Usually transient, ignore if activation succeeds
  - Build errors → Fix the NixOS configuration issue

  **Zero tolerance policy**: Do NOT proceed to other tasks until deployment errors are resolved.
---


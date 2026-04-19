# hermes-agent-patch: Wiring instructions
#
# This file documents the exact changes needed to activate the patch.
# DO NOT apply without user confirmation.
#
# ── File: hosts/nexus/services.nix ──────────────────────────────────────────
#
# Add near the top of the file (after the { config, pkgs, inputs, ... }: block):
#
#   patchedHermes = pkgs.callPackage ../../packages/hermes-agent-patch.nix {
#     hermes-pkg = inputs.hermes-agent.packages.x86_64-linux.default;
#   };
#
# Then add inside services.hermes-agent:
#
#   services.hermes-agent = {
#     enable = true;
#     package = patchedHermes;    # ← ADD THIS LINE
#     addToSystemPackages = true;
#     ...
#   };
#
# ── What the patch does ────────────────────────────────────────────────────
#
# In run_agent.py line 6789, the condition:
#
#   if self.provider == "custom" and self.reasoning_config
#      and isinstance(self.reasoning_config, dict):
#
# is changed to:
#
#   if self.provider == "custom" and self.reasoning_config
#      and isinstance(self.reasoning_config, dict)
#      and ("ollama" in self._base_url_lower
#           or ":11434" in self._base_url_lower
#           or (self.base_url and is_local_endpoint(self.base_url))):
#
# This ensures `think=false` is only sent to endpoints that understand it:
#   - Ollama instances (URL contains "ollama" or port 11434)
#   - Local endpoints (localhost, 127.0.0.1, *.svc.cluster.local, etc.)
#
# Remote OpenAI-compatible providers (NVIDIA NIM, Z.AI, etc.) are excluded,
# preventing HTTP 400 errors when reasoning_effort is set to "none".
#
# ── Providers affected by this change (from services.nix) ─────────────────
#
# Provider         | base_url                              | Receives think=false?
# -----------------|---------------------------------------|----------------------
# zai              | https://api.z.ai/api/coding/paas/v4   | NO (not local/ollama)
# nvidia-nim       | https://integrate.api.nvidia.com/v1   | NO (was causing 400!)
# ai-gateway       | http://127.0.0.1:8080/v1              | YES (local endpoint)
# lmstudio         | http://127.0.0.1:1234/v1              | YES (local endpoint)
# llama-cpp-zephyr | http://llama-server-...svc.cluster... | YES (local endpoint)
# llama-cpp-sentry | http://llama-server-...svc.cluster... | YES (local endpoint)
#
# ── Rollback ───────────────────────────────────────────────────────────────
#
# Remove the `package = patchedHermes;` line and the `patchedHermes` let binding.
# Rebuild. The original unpatched package is restored.

## remove-repository-agent-routing — Use extension model settings

**Goal:** New sessions inherit development-system model routing without repository overrides.

**Files:** AGENTS.md; .agents/skills/agent-routing/SKILL.md; scripts/check-agent-routing; scripts/test-agent-routing-validator; docs/decisions/2026-10.md.

**Interfaces:** The extension's existing model configuration remains unchanged; .codex/config.toml continues inheriting global settings.

**First failing test:** Not applicable to deletion-only instruction cleanup; the recorded tdd.red-first departure uses direct policy-discovery inspection and unchanged flake checks instead.

**Steps:**
1. Inspect active instructions and references to the obsolete policy and validators.
2. Remove the routing-only instruction files and policy-specific validators; preserve historical decisions.
3. Check remaining active references, run flake checks, review, commit and push.

**Run:** `git diff --check`; active-instruction/reference sweep; `nix flake check -L`.

**Expected:** No active repository routing override or validator remains; existing flake checks pass. Already-running sessions retain their loaded policy until reloaded.

**Out of scope:** Extension settings, global skills, historical decision records, Codex global defaults, and unrelated application configuration.

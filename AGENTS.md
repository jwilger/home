# Repository Guidelines

## Agent routing

Before selecting a subagent model or reasoning effort, read
`.agents/skills/agent-routing/SKILL.md`. It is the canonical policy for
orchestration, delegation contracts, progressive escalation, and review
returns in this repository.

Do not apply routing-policy edits to an already running session. After this
guidance or `.codex/config.toml` changes, finish and review the increment, then
reload every session working in this repository before using the new policy.

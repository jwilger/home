## Plans and active goals

Every actionable implementation plan produced in Plan Mode must begin with an execution step to establish an active goal for completing the entire approved plan.

When execution is authorized and Plan Mode has ended, activate that goal before implementation. Reuse a matching active goal; surface a conflicting unfinished goal instead of replacing it silently. Set a token budget only when the user explicitly requests one.

The goal covers the plan’s acceptance criteria, verification, and any authorized delivery and cleanup. Keep it current as the user changes scope. A partial implementation, open PR, or pending required reload is not completion.

This instruction authorizes goal creation for approved plans; it does not authorize implementation while still in Plan Mode.

## Sandbox recovery

When an already-authorized operation fails because of filesystem or network sandbox restrictions, attempt the supported approval or escalation mechanism before reporting a blocker or asking the user to change permissions. A sandbox denial alone does not establish that the operation is unavailable.

Retry the exact blocked operation with the narrowest necessary elevation, including routine Git metadata writes such as `.git` updates. If the tool has no direct escalation option, investigate a supported equivalent that preserves the operation's scope and applicable restrictions. Keep unrelated operations and services within their existing boundaries.

Respect an explicit approval rejection. Continue unaffected work and safe alternatives; if completion remains blocked, report the rejected operation, the stated reason, and the specific action needed from the user. Do not ask the user to configure permissions when an available escalation path can complete the authorized work.

## Context-efficient tool use

- Prefer Serena for repository exploration: activate the exact project/worktree,
  then use symbol overviews, symbol lookup, and references before reading whole
  files. Read complete bodies when needed to understand behavior.
- Generated repository-local `.serena/` directories can be committed. Include
  their `.gitignore`; it excludes `/cache` and `/project.local.yml`, keeping
  shared project configuration separate from generated cache and local overrides.
- Use RTK for supported noisy shell commands; the native hook normally rewrites
  them automatically. Use `rtk proxy <command>` when full output is needed.
- Use Context7 for targeted library documentation, specifying the library ID and
  version when known. Retrieve only the material needed for the current question.
- Use code mode (`exec`/`wait`) to compose tool calls and deterministic calculations.
  Batch independent reads, sequence dependent calls and mutations, and inspect
  every result. Filter intermediate data before emitting selected evidence.
- Keep complete logs and large artifacts on disk; return paths, counts, selected
  fields, and relevant failures. Expand to raw output when summaries omit evidence
  needed for correctness. Keep tool configuration stable within a session to
  preserve prompt caching.

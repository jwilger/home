---
name: agent-routing
description: Use when selecting a model or reasoning effort for orchestration, delegation, planning, implementation, review, or escalation.
---

# Agent Routing

Use the least expensive tier appropriate to the task's current risk. The main
session coordinates and preserves evidence; delegated workers own bounded work.
Select from the current runtime's allowed model names. If a named model is not
available, stop and report the unavailable policy tier instead of silently
substituting another model.

## Default routing

| Task category | Model | Effort | Reason |
| --- | --- | --- | --- |
| Main-session orchestration | `gpt-5.6-sol` | `low` | Coordinate, track evidence, delegate, and escalate at decision points without sustaining elevated reasoning. |
| Bounded, approved implementation | `gpt-5.6-luna` | `max` | Execute a clear contract or approved RED test within explicit, non-overlapping file ownership and a small expected scope. |
| Trivial exploration, inventories, typo fixes, mechanical edits | `gpt-5.6-luna` | `low` | Perform disposable or deterministic work with little synthesis. |
| Modest synthesis during otherwise trivial work | `gpt-5.6-luna` | `medium` | Resolve a small amount of local ambiguity without crossing an architectural boundary. |
| Architecture, planning, substantive implementation review, and non-trivial review corrections | `gpt-5.6-sol` | `high` | Reason across boundaries, assess tradeoffs, or correct a rejected non-trivial implementation. |
| Exceptional architecture or planning with broad coupling, ambiguity, or competing designs | `gpt-5.6-sol` | `xhigh` | Resolve unusually broad or ambiguous design choices; this is not normal planning. |
| Demanding concurrency, recovery, EventCore ownership or contracts, transaction semantics, cross-cutting architecture, or conflicting evidence | `gpt-6-astra` | `high` | Handle the hardest ownership, semantics, recovery, or evidence-resolution decisions. |

Terra is not a routine routing tier. Select Terra only for explicitly
disposable, read-only bulk inventory when measured evidence shows it is
materially more efficient and will not create meaningful rework.

## Delegation contract

Every delegated task states its selected model and reasoning effort. It also
states the reason whenever that selection differs from the default for its task
category. A bounded implementation delegation additionally includes:

- the clear contract or approved RED test;
- explicit, non-overlapping file ownership;
- the small expected implementation scope;
- required verification and the evidence to return; and
- stop conditions for any risk boundary below.

The main session retains orchestration, evidence tracking, integration, and
decision-point escalation. It does not delegate overlapping writes or ask a
worker to resolve an unstated architecture decision.

## Progressive escalation

1. Start approved, tightly bounded implementation with Luna/max.
2. Escalate before implementation when the task has an unclear contract,
   crosses multiple logical boundaries, involves persistence, replay, or
   concurrency, affects public compatibility or security, introduces a new
   abstraction, shows unexpected test behavior, or likely requires an
   architecture decision.
3. When independent review rejects implementation for a non-trivial reason,
   assign corrective implementation to Sol/high. Do not repeatedly retry the
   rejected work with Luna.
4. Use Sol/xhigh only for exceptional architecture or planning with broad
   coupling, ambiguity, or several competing designs.
5. Use Astra/high only for its demanding concurrency, recovery, EventCore,
   transaction, cross-cutting architecture, or conflicting-evidence scope.
6. The reviewer must classify every returned change as mechanical enough for
   Luna or as requiring escalation, and explain why.

If risk emerges during implementation, stop the worker at the current evidence
boundary. The main session records the evidence, chooses the qualifying tier,
and redispatches with a revised contract before implementation continues.

## Review decisions

Substantive implementation review uses Sol/high. A review result reports:

- acceptance or the specific rejected behavior;
- supporting file, test, or command evidence;
- whether each returned change is mechanical enough for Luna or requires
  escalation; and
- the reason for that classification.

Typographical or purely mechanical review can use Luna/low. Any returned change
that alters behavior, boundaries, abstractions, compatibility, security,
concurrency, persistence, or transaction semantics is non-trivial.

# ADR 0001: Run Hindsight inference on the M4 over Tailscale

## Status

Accepted — John authorized the all-local migration.

## Context

Hosted OpenAI extraction and embeddings are too expensive. Hindsight runs in a
Home Manager-owned daemon with PostgreSQL/pgvector; the M4 already serves Ollama
over Tailscale at `100.98.58.77:11434`. Existing memories must not be lost or
searched using vectors from a different embedding space.

## Decision

Use native Ollama `qwen3-coder:30b` for all LLM operations and its OpenAI-compatible
embedding endpoint for `qwen3-embedding:0.6b` (1,024 dimensions). Keep RRF reranking.
Remove the startup dependency on paid credentials, explicitly set per-operation
routes, and provide no hosted fallback. Back up the private database and daemon
profile before replacing existing vectors; preserve facts and other stored data.

Alternatives: keeping hosted embeddings would retain a billing dependency and
split routing. Starting with an empty database would discard accumulated memory.
Re-extracting all documents would unnecessarily change facts and consume much more
inference than replacing vectors.

## Consequences

Inference has no OpenAI usage charges. The Mac must remain awake and on Tailscale;
outages cause errors rather than paid fallback. Local extraction may be slower or
less accurate, so verify structured output and an actual retain/recall round trip.
Limit LLM and embedding concurrency for the shared Mac. This trusts the existing
Tailscale boundary: do not expose unauthenticated Ollama to the public Internet.
Store backups outside Git with owner-only permissions. Rollback requires the old
database vectors and matching old provider configuration together; never mix them.

## Revisit when

Revisit if extraction quality, queue latency, memory pressure, or Mac availability
makes this unreliable, or if a different local model/server materially improves
cost-free operation. Changing the embedding model requires another migration.

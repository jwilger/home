# Hindsight on the M4

## Runtime

Home Manager owns the daemon, PostgreSQL and configuration on the Linux host.
Ollama runs on the Mac at `100.98.58.77:11434`, reachable only through the trusted
Tailscale network. Do not publish Ollama's unauthenticated API to the Internet.

Required models:

- `qwen3-coder:30b`: extraction, reflection, consolidation and page refresh.
- `qwen3-embedding:0.6b`: 1,024-dimensional embeddings.

The LLM context window is 32,768 tokens and requests are limited to one concurrent
LLM call. Embedding batches are eight texts with one request in flight. There is
no cloud fallback. `ollama` is a dummy API key, not a credential. The startup
wrapper no longer sources `~/.envrc` or fetches an OpenAI key. The managed
`~/.hindsight/openai.env` filename is retained for upgrade compatibility.

To diagnose availability without sending any memory content:

```sh
curl --noproxy '*' --fail http://100.98.58.77:11434/api/tags
curl --noproxy '*' --fail http://127.0.0.1:9077/health
systemctl --user status hindsight-daemon-start.service
```

A healthy API alone does not prove inference works. Verify an actual synthetic
retain and recall through Hindsight after changes. Check that per-operation and
bank-specific model routes do not override the local settings. Do not print keys,
profile contents, private memory text or full process environments into logs.

## Changing an existing embedding space

Changing a model name or vector dimension is not a migration. Old vectors and new
queries are incompatible even if their dimensions happen to match. Never delete
facts to make Hindsight's dimension check pass.

Use this sequence for each host with an existing database, before activating the
new routing configuration:

1. Stop daemon-start and history-import timers and services, then gracefully stop
   the API process. Confirm port 9077 is no longer serving. Keep PostgreSQL up.
2. Create an owner-only backup directory under
   `~/.local/state/hindsight/backups/`. Save a custom-format `pg_dump`, the managed
   settings, daemon profile and profile metadata. Check the archive with
   `pg_restore --list` and record its SHA-256. Backups can contain credentials and
   private memories: never commit them.
3. Clone the offline database, retaining the original unchanged. Work only on the
   clone until every check passes.
4. Generate replacement vectors for **every** row in `memory_units` and
   `mental_models` into temporary 1,024-dimensional columns. Match Hindsight's
   date/entity augmentation for facts and `name + " " + content` for mental models.
   Use only the Mac's embedding endpoint; do not re-extract documents. Sanitize
   recognizable credential literals before sending text. Validate response counts,
   dimensions, finite values and nonzero vectors. Checkpoint batches so failures
   can resume without touching the original.
5. Compare all tables' row counts and hashes of non-vector data with the original.
   In one transaction, replace both embedding columns from the staging columns,
   retaining/rebuilding the existing vector indexes. Recheck all non-vector data
   and dimensions. Keep documents, facts, entities, links, bank configuration,
   knowledge pages and histories intact.
6. While the API remains stopped, rename the original database to a rollback name
   and give the verified clone the configured `hindsight` name. Remove old paid
   credentials from the active daemon profile; keep the private backup.
7. Activate the built Home Manager generation, start the daemon and check its
   effective routes. Verify a synthetic retain/recall round trip and semantic
   recall against existing memories before restoring the normal timers.

Do not copy these operations to another machine without first checking its
installed Hindsight version and schema. This is an operational migration, not an
automatic activation hook; another host's database must be handled separately.

## Rollback

Stop the new daemon and timers. Preserve the migrated database under another name,
restore the original database's name (or restore the dump into an empty database),
and restore its matching old profile and managed configuration. Old vectors require
the old embedding provider; switching only configuration back is unsafe. Returning
to a paid provider requires an explicit decision, not an automatic fallback.

Keep the original database and backup until local inference has been accepted.

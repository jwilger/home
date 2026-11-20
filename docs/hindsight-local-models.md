# Hindsight local inference

## Runtime

Home Manager owns the daemon, PostgreSQL and embedding runner on the Linux host.
The Mac's Ollama at `100.98.58.77:11434` serves `qwen3-coder:30b` for extraction,
reflection, consolidation and page refresh. It is reachable over the trusted
Tailscale network. Do not publish Ollama's unauthenticated API to the Internet.

The Linux CPU runner (`hindsight-embeddings.service`, `127.0.0.1:11435`) serves
`qwen3-embedding:0.6b` for all embeddings. Hybrid page search needs a query
embedding; serving it separately prevents it from queuing behind 30B generation.
The manifest and weights are pinned to the same 1,024-dimensional Q8_0 model that
produced the stored vectors. This routing change does not require re-embedding.
There is no search fallback and no cloud inference fallback.

The LLM context window is 32,768 tokens with one concurrent LLM call. Embedding
batches are eight texts with one request in flight. `ollama` is a dummy API key,
not a credential. `~/.hindsight/openai.env` is a legacy filename for the managed
inference and database settings.

## Activating a routing change

Switch the Home Manager generation and start `hindsight-embeddings.service`.
Confirm it is ready before restarting Hindsight. The detached API does not
reload environment changes: stop `hindsight-daemon-start.timer`, send `SIGTERM`
to the Hindsight API process listening on 9077 (confirm its PID with `ss -ltnp`),
and wait for it to exit. Then start `hindsight-daemon-start.service` and restore
the timer. Keep PostgreSQL running; this does not change the database.

```sh
systemctl --user status hindsight-embeddings.service
curl --noproxy '*' --fail http://127.0.0.1:11435/api/tags
curl --noproxy '*' --fail http://127.0.0.1:9077/health
curl --noproxy '*' --fail --get --max-time 7 \
  http://127.0.0.1:9077/v1/default/banks/coding-agent%3A%3Ahome/knowledge-base/search \
  --data-urlencode 'q=local inference and agent memory' --data 'limit=3' \
  | jq '.results | map(.name)'
```

A healthy API alone does not prove inference works. Verify an actual synthetic
retain and recall when changing model configuration. Check that per-operation and
bank-specific routes do not override the local settings. Do not print keys,
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
   Use the target embedding endpoint; do not re-extract documents. Sanitize
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

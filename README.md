# Shared Home Manager configuration

Public, reusable Home Manager configuration for John Wilger's Linux workstations.

The flake exports `homeModules.jwilger`, `homeModules.default`, and standalone
configurations for `jwilger@gregor` and `jwilger@jwilger-t14`. Consumers must
set `jwilger.hostProfile` and should pin this flake to an immutable commit.

```nix
home-manager.users.jwilger = {
  imports = [ inputs.jwilger-home.homeModules.jwilger ];
  jwilger.hostProfile = "gregor";
};
```

Run `just check`, or build either standalone profile with
`just build jwilger@gregor` and `just build jwilger@jwilger-t14`.

Noctalia starts from a repository-owned immutable baseline that activation
copies into writable user configuration. After intentional UI changes, run
`just capture-noctalia`; it copies only the reviewed allowlist back to the
repository and leaves the Git diff uncommitted for inspection. Generated state
and plugin data are never captured.

## Hindsight memory

Home Manager configures a local Hindsight daemon and installs its Codex hooks,
MCP server, and agent skill. The OpenAI key is read at daemon startup from the
`OpenAI API key` field of the `Hindsight` item in the Personal 1Password vault
of account `MRECLJED3JFMFCCB6ZS3D5AIZU`. Replace the
`REPLACE_WITH_OPENAI_API_KEY` placeholder in that field; no key is stored in
this repository or the Nix store. The same key powers extraction and OpenAI
embeddings, which incur API usage; retrieval uses RRF without a local reranker.
Hindsight uses a Home Manager-managed PostgreSQL 18 instance with pgvector in
`~/.local/share/hindsight/postgres`, accessible only through a private Unix
socket. It does not use Hindsight's bundled PostgreSQL or the system NixOS
configuration.

The `hindsight-daemon-start` timer retries startup every five minutes. Once its
`/health` endpoint is ready, `hindsight-codex-history-import` imports existing
Codex transcripts by their recorded working directory and then records a
completion marker in `~/.local/state/hindsight/codex-history-imported-v2`. Its
timer retries hourly until the import succeeds. Start a new Codex session after
activation to load the new hooks and MCP server.

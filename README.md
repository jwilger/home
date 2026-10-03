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

## ChatGPT desktop updates

The `Update ChatGPT desktop` GitHub Action runs nightly at 09:23 UTC and can
also be started with **Run workflow**. It downloads OpenAI's latest amd64 deb,
updates the version and SHA-256 hash together, builds the package, and commits
the change to the default branch only after the build succeeds. Unchanged
downloads produce no commit. The repository must allow Actions to write to
the default branch; branch protection is not bypassed.

For a local update, run `python3 scripts/update-chatgpt` with Python 3.11+,
`curl`, and `dpkg-deb` available. Review the resulting diff before committing.
Apply the updated configuration with your usual Home Manager rebuild.
The upstream URL is mutable, so an uncached build of an older pin can fail
its hash check after OpenAI replaces the download.

## Hyprland computer-control feasibility

See [the transport, security and verification plan](docs/hyprland-computer-control.md)
for voice-driven desktop control. The optional
`jwilger.computerControlProbe.enable` readiness probe is disabled by default.
It checks local prerequisites only; it does not grant assistant access or
provide screenshot/input control.

## Voice dictation

Voxtype replaces the old `voice-dictation` script. After activation, run
`voxtype setup --download` once to fetch the local `base.en` Whisper model.
Hyprland starts its user service on login. Press **Scroll Lock** to begin recording
and again to transcribe into the focused window; Noctalia shows start/stop
notifications and its microphone privacy indicator. Voxtype's built-in evdev
hotkey is disabled, so no `input` group membership is needed. Check
`systemctl --user status voxtype` if dictation does not start. New Lua
keybindings take effect after logging out and back in; `hyprctl reload`
does not re-register them. To start the daemon without logging out after a
Home Manager switch, run `systemctl --user start voxtype.service`.

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

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

## Hyprland workspaces and layouts

On the T14, **Super+1–9** selects a logical workspace in the bank belonging to
the currently focused monitor. Clicking a Noctalia workspace pill likewise
changes only that monitor's bank. Hyprland still needs unique physical
workspaces: the StudioDisplay uses IDs 1–9 and eDP-1 uses 11–19, named
`1-laptop` through `9-laptop`. Both bars display the logical 1–9 labels in
numeric order. The StudioDisplay is matched by description, not its changing
DP connector number.

- **Super+Shift+1–9:** move the focused window to that logical workspace on its
  current monitor and follow it
- **Super+[ / Super+]:** move the focused window to the matching workspace on the
  left/right monitor and follow it. **Super+Ctrl+Shift+H/L** and
  **Super+Ctrl+Shift+Left/Right** are aliases. These replace the old bracket
  `movewindowto` dispatcher, which is absent from the pinned Hyprland.
- **Super+Ctrl+H/L or Left/Right:** focus the left/right monitor in every layout
- **Super+H/J/K/L or arrows:** focus in that direction; in monocle, left/up selects
  the previous window and right/down selects the next
- **Super+Shift+H/J/K/L or arrows:** move windows; scrolling retains horizontal
  column swaps when an adjacent column exists, with native movement at edges
- **Super+C, Super+R, Super+Minus/Equal:** scrolling-only fit and column sizing;
  safely do nothing in other layouts or without a tiled window

When only one display is connected, numbered shortcuts operate its own bank and
monitor-transfer shortcuts safely do nothing. Hyprland preserves any windows
migrated from an unplugged output; their workspaces remain available in the bar
and return to their assigned display when it reconnects. Workspace events,
reloads, startup, and hotplug do not automatically reconcile the two banks.
Gregor keeps its ordinary single-bank 1–9 workspace configuration.

Home Manager installs the pinned upstream **Hyprland Layout Switcher** plugin
(`maddingo/hypr-layout-switcher`, version 0.1.1) and enables it in both Noctalia
baselines. The top-left bar is workspaces → spacer → layout switcher → spacer →
active window title. Click the switcher to cycle **dwindle → master → monocle →
scrolling**. All four are built into the pinned Hyprland 0.55.4; T14's compositor
is system-owned and must provide the same Lua APIs.

The upstream widget follows the globally focused workspace, even when clicked
on the other monitor's bar. Layout changes apply to that physical workspace,
so each monitor can intentionally use a different layout. They are runtime choices:
reloading Hyprland restores this repository's scrolling defaults. Noctalia's
locally installed plugin takes precedence over a store-downloaded copy. If a
hand-copied plugin already occupies `~/.local/share/noctalia/plugins/hypr-layout-switcher`,
back up that directory before activating Home Manager; no existing plugin files
are forcibly deleted by this configuration.

Run the focused, hardware-free regression check with
`nix build .#checks.x86_64-linux.hyprland-desktop-controls`. It executes the real
controller against a stateful compositor double, loads the actual generated Lua
for both profiles, validates the pinned plugin plus Noctalia bar/settings, and
runs the actual pinned Hyprland's `--verify-config` parser without starting a session.
Run `just check` for the complete configuration. After a normal activation and a
fresh login, also verify both monitors, bar clicks, window transfers, docking,
and each layout in the live session; simulated tests cannot prove compositor
animation, actual monitor timing, or rendered bar geometry.

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

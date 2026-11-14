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

## OBS podcast recording (T14)

Open **OBS Podcast Studio** or run `obs-podcast` for editable 1080p30 solo,
screen, interview and panel presets using the OBSBOT camera and Blue USB mic.
Run `obs-podcast-setup links` for private VDO.Ninja guest/cohost invitations;
guests need only a browser. Recording includes a full audio mix plus isolated
host, guest and selected computer-audio tracks. Select your screen once through
the Wayland portal and route clip applications to **Podcast-Program** in
`pavucontrol`; leave the director browser on your real headphones.

See [the podcast runbook](docs/obs-podcast.md) for first-use setup, guest-local
recording for best quality, avoiding doubled audio, Zoom/Meet fallback, and a
preflight checklist. No recording, streaming or guest invitation starts at login.

## OBSBOT camera controls

Both workstation profiles install [Tiny4Linux](https://github.com/OpenFoxes/Tiny4Linux)
2.2.1 with dashboard and widget launchers, its `t4l` command, and
[Camset](https://github.com/azeam/camset), the upstream recommendation for standard
camera controls. `v4l2-ctl` is also available for inspecting and adjusting controls.

Open Tiny4Linux from the application launcher, or use:

```sh
t4l wake
t4l tracking normal
t4l info
```

Keep a camera preview open and a person in view when checking AI tracking.
`t4l tracking close-up` requests close-up framing; `t4l tracking static` disables
tracking. Check the reported AI mode: a successful command alone, or a status of
`Static`, does not confirm that the camera has acquired a subject.

Normal tracking is restored automatically when a video application opens the
camera after an idle period. The helper preserves an already active framing mode
and lets you disable tracking during the current session. It does not open a
video stream or wake a sleeping camera. To stop automatic restoration, run
`systemctl --user stop obsbot-tracking-resume.service`.

For manual zoom, open **Camset**, select the OBSBOT capture device, and adjust
**Zoom, Absolute**. The connected Tiny 2 Lite exposes a 0–100 zoom range. To inspect
devices from the terminal, run `v4l2-ctl --list-devices`, then use the capture node
shown for the camera (replace `/dev/videoN` below):

```sh
v4l2-ctl --device /dev/videoN --get-ctrl zoom_absolute
v4l2-ctl --device /dev/videoN --set-ctrl zoom_absolute=25
```

Camera controls apply to other video applications too. Some gesture settings and
the creation of preset positions may require one-time setup in OBSBOT Center on
Windows or macOS, as described in the Tiny4Linux README.

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

## Codex CLI and global agent tools

Home Manager installs the pinned official Codex CLI bundle on both profiles,
including its companion runtimes. The CLI and ChatGPT Desktop share the default
`~/.codex` configuration and login. The desktop launcher inherits `CODEX_HOME`
when explicitly supplied by a project environment. The former `~/.codex-chatgpt`
directory is left intact as an archive; its settings and credentials are not
merged over the default directory.

Claude Code uses its default `~/.claude` directory; neither Claude launcher sets
`CLAUDE_CONFIG_DIR`. Put project settings in `.claude/settings.json` (or
`.claude/settings.local.json` for private settings), and Codex project settings
in `.codex/config.toml`. Desktop app UI data remains in the apps' native
`~/.config/Claude` and `~/.config/ChatGPT` directories.

Shared additions are RTK, billion-context, and Hindsight. Apps, plugins, MCP
servers, skills, and native memory use their upstream defaults or user settings.
On the first activation of this configuration, a backed-up migration removes
the disabling overrides written by the former lean CLI baseline. Later global
choices are preserved. Put project-specific restrictions in project config.

Home Manager manages concise helper guidance in `~/.codex/AGENTS.md`.
Activation runs `reconcile-codex` to reapply writable defaults and compose hooks.
It preserves trusted projects, login/session state, and project configuration.
Changed files and the previous `~/.local/bin/codex` entry receive timestamped
`.home-manager-backup.*` backups. Invalid input is rejected before config writes.
Existing Serena data and shared skill directories are retained. Serena and
Context7 are no longer installed or started globally by this module. The obsolete
Herdr session hook is removed; standard Hindsight hooks remain.

RTK filters supported shell output through a native Codex hook. Use
`rtk proxy <command>` for raw output with tracking, or `RTK_DISABLED=1 <command>`
to bypass rewriting. `rtk gain` estimates shell-output savings, not total cost.
Billion-context continues to use the persistent proxy described below.

### Project configuration

Existing project configs remain unchanged; activation does not migrate global
integrations into repositories. Add optional tools explicitly to a trusted
project's `.codex/config.toml`. For example, replace the command below with an
executable supplied by the project's environment:

```toml
[mcp_servers.project_tool]
command = "/absolute/path/to/project-mcp"
enabled = true

[features]
plugins = true

[plugins."development-system@ai-plugins"]
enabled = true
```

Use the same project configuration to disable unwanted features, plugins, or
MCP servers with `enabled = false` where supported. Ensure tool runtimes are
available in the project shell. Add project-local skills in `.agents/skills`.
Untrusted project config is ignored.

Hindsight's Codex-only policy automatically searches up to three knowledge pages
and refreshes guidance every ten turns. Ten is this configuration's context
policy, not an upstream recommendation. Session capture, repository banks,
standard hooks, hourly page maintenance, and deliberate deeper reflection remain
available. Claude and shared server settings retain their existing behavior.

The `Update Codex CLI` Action runs nightly at 09:23 UTC or by manual dispatch.
It validates the latest stable official release, its bundle metadata and upstream
checksum, then updates the version/hash together and builds the package before
committing to the default branch. Unchanged releases produce no commit. It shares
write concurrency with the ChatGPT updater. The workflow becomes active after
publication; apply updated pins with the usual Home Manager rebuild. Local updates
can be prepared with `python3 scripts/update-codex`; review the diff before commit.
The former first-login installer and weekly updater are retired.

Code mode uses Codex's upstream defaults. Activation removes the former
`code_mode` and `code_mode_only` overrides from the writable configuration
instead of forcing either value. Global instructions suggest code-mode
orchestration only when that capability is available.

Restart CLI sessions after activation to load the managed defaults and hooks.

### Billion Context with the shared Codex daemon

Home Manager runs a pinned Billion Context proxy as `bili.service` on
`127.0.0.1:8787`. Its Codex MCP companion exposes reversible conversation
compression, decompression, and context search. Continue using plain `codex`
and `codex agents` from any shell; no `bili codex` launcher is needed.

The managed `~/.codex/.env` routes Codex traffic through the persistent proxy
and trusts its combined public-root/local-CA bundle. ChatGPT Desktop shares
this Codex environment; other applications keep their own proxy settings.
The proxy's private CA and session history remain in the user's
data directory, outside the Nix store. The service uses a store configuration
and disables self-updates; change the package pin to update it.

After the first activation, check `systemctl --user status bili.service`, then
run `codex app-server daemon restart` to load the new environment. Restarting
interrupts attached sessions. A running daemon retains its previous environment
until restarted. Do not use `bili codex`: its launcher forces embedded mode.
The proxy must remain running while Codex uses it. Inspect its journal with
`journalctl --user -u bili.service`; its local UI is
`http://127.0.0.1:8787/__bili/`. Tool availability alone does not prove traffic
is compressed; verify the proxy's session activity and compression state.

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
MCP server, and agent skill. All inference runs on the MacBook Pro M4's Ollama
server at `http://100.98.58.77:11434` over Tailscale:

- LLM operations: `qwen3-coder:30b` using the Ollama provider.
- Embeddings: `qwen3-embedding:0.6b`, 1,024 dimensions, through Ollama's
  OpenAI-compatible `/v1` API. The provider name `openai` here describes the
  protocol; requests do not go to OpenAI.
- Retrieval: RRF without a paid reranker.

There is no hosted fallback and no OpenAI credential is needed. The Mac must stay
awake, connected to Tailscale, and running Ollama. If it is unavailable, memory
operations fail rather than spend money. The legacy `~/.hindsight/openai.env`
filename is retained, but now contains only local inference/database settings.
See [the migration runbook](docs/hindsight-local-models.md) before switching an
existing database to a different embedding model.
Hindsight uses a Home Manager-managed PostgreSQL 18 instance with pgvector in
`~/.local/share/hindsight/postgres`, accessible only through a private Unix
socket. It does not use Hindsight's bundled PostgreSQL or the system NixOS
configuration.

The coding-agent runtime is pinned in `modules/home/hindsight.nix` and runs
from the immutable Nix store. Home Manager owns its updates; session auto-update
is disabled. Both harness installers and history imports share an installation
lock. Installer timers run at startup and weekly; the installers are not attached
to `default.target`, so NixOS user-manager reloads do not reinstall them.

The `hindsight-daemon-start` timer retries startup every five minutes. Once its
`/health` endpoint is ready, `hindsight-codex-history-import` imports existing
Codex transcripts by their recorded working directory and then records a
completion marker in `~/.local/state/hindsight/codex-history-imported-v2`. Its
timer retries hourly until the import succeeds. Start a new Codex session after
activation to load the new hooks and MCP server.

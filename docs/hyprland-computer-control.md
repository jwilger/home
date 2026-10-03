# Hyprland computer control: session-local adapter and verification

Research and device verification date: 2026-10-03. Initial research baseline: `96b26df`.

## Recommendation

The authorized connected-computer task has demonstrated screenshot delivery
and harmless typing on this T14. The next increment is a bounded session-local
pointer adapter. Installing an automation CLI alone does not establish that an
arbitrary assistant session can observe and operate the desktop; use the
verified task route and keep each live action within the owner's authorization.

Use the supported connected-computer task route with its inherited unlocked
Hyprland session. A session-local STDIO MCP adapter remains a possible separate
extension for local desktop Codex, but no MCP registration or persistent
transport is added here. This task route does not establish that the cloud
dot's voice session can call a local MCP server directly.

The **opt-in read-only readiness probe** remains disabled in both profiles.
A separate, explicitly invoked pointer-adapter package provides bounded
session-local input for authorized tasks. It is not added to either Home Manager
profile and is not activated by this PR. Neither component registers MCP, starts
a service, grants permissions, adds credentials, or exposes a network listener.

## Three boundaries that must be verified separately

1. **Native Linux Computer Use:** the Linux desktop app exists, but official
   documentation explicitly excludes Computer Use from the Linux preview.
   NixOS is also outside its formally supported distro list. Native Wayland
   support remains experimental. A working desktop login therefore does not
   establish a working GUI-control backend. [Linux desktop documentation][linux]
2. **Local desktop/Codex host:** local STDIO MCP and Streamable HTTP MCP are
   documented, with configuration belonging to that Codex host. Local MCP
   availability under cloud orchestration must be checked separately. The web
   app does not read a machine's local Codex config. [MCP documentation][mcp]
3. **This dot and voice:** dot access to a personal computer is separate from
   its ordinary Codex/Work connection. An authorized local task is the supported
   execution route. Voice can coordinate supported tasks but doesn't grant
   additional permissions or prove tool availability. Verify the actual local
   task, then an actual voice-initiated task. [Computer connections][dots],
   [Voice documentation][voice]

A hosted custom plugin is another architecture, not an automatic bridge to
localhost. It would need a supported transport, authentication, session binding,
and explicit approval of new persistent access. No public desktop-control
endpoint or tunnel is proposed here. [Plugin packaging][plugins]

## Local projects worth using

| Project | Useful capability | Important gap or cost |
| --- | --- | --- |
| [Hyprland IPC / hyprctl][hyprctl] | Window, monitor, workspace, cursor and lock-state queries; compositor-specific actions | No image transport or assistant authorization. This repository uses Lua configuration; old `hyprctl dispatch focuswindow ...` examples are not a safe compatibility assumption. |
| [grim][grim] | Screenshot of a monitor or region | No input. The image's pixel coordinates must be mapped to compositor logical coordinates, including scale, transform and monitor origin. |
| [wtype][wtype] | Text, key and modifier events through Wayland virtual keyboard | Upstream 0.4 has no pointer API. Key release is tied to process/virtual-keyboard lifetime. |
| [wlrctl][wlrctl] | Virtual pointer relative movement, click and scroll; basic keyboard/toplevel operations | Its upstream labels it experimental. The 0.2.2 CLI exposes no sustained button-down/path/button-up drag. One-shot calls must not be treated as a complete computer-use backend. |
| [ydotool][ydotool] | Broad keyboard and mouse emulation through Linux uinput | Requires its daemon and `/dev/uinput` access. This crosses a system permission boundary and is unnecessary for a first Hyprland-specific implementation. |
| [wayvnc][wayvnc] | Persistent capture/input over RFB for compatible Wayland sessions | Adds another server, authentication and viewer/transport layer. There is no verified native dot-to-RFB consumer here. Do not open a listener merely to make GUI control possible. |

These are upstream, packaged building blocks, not endorsements of every current
release as production-ready. In particular, wlrctl has a small experimental
surface. Prefer the pinned distro packages over an unreviewed automation fork.

Hyprland 0.55.4's [protocol manager][protocols] implements the screencopy,
virtual-keyboard and virtual-pointer protocols used above. Runtime availability
and permissions still need checking. A screen-sharing portal is not proof of
input support: the upstream Hyprland portal's [RemoteDesktop work][portal-prs]
was still open when checked. Do not assume a generic RemoteDesktop/libei client
works merely because screen sharing works.

## What this repository actually pins

- Root nixpkgs: `6d663c0533ff269008fb84e45930151e37c99db9`.
- Home Manager: `ec172013fa62135f58fb58dd17ae9651e8f39727`.
- That nixpkgs revision supplies Hyprland **0.55.4**, grim **1.5.0**,
  wtype **0.4**, and wlrctl **0.2.2**.
- `modules/home/desktop/hyprland.nix` uses Lua. For `jwilger-t14`,
  `package = null` and `portalPackage = null`: the NixOS host owns those
  packages. Its running Hyprland version is **not established by this flake**.
- UWSM owns the graphical session; the Home Manager Hyprland service is disabled.
  A future adapter must join that session, not create a competing compositor or
  session target.
- grim is already supplied through Noctalia and wtype through Voxtype.
- `modules/home/desktop/chatgpt.nix` packages desktop **26.930.31730** and sets
  `CODEX_HOME=$HOME/.codex-chatgpt`. Local MCP configuration for that desktop
  host therefore cannot simply be assumed to come from `~/.codex/config.toml`.
  Existing desktop and CLI identities/configurations must remain separate.

## Use the read-only probe after approval

For a reviewed Home Manager configuration, the option is:

```nix
jwilger.computerControlProbe.enable = true;
```

Enabling it installs `hyprland-control-probe` with pinned detection dependencies.
It intentionally finds `hyprctl` on the host's existing PATH so that the T14
keeps using its system compositor's client. There is no service or startup hook.

Run `hyprland-control-probe` **inside the authorized executor for the existing
graphical session**. Exit 0 means the probe found local prerequisites; exit 1
means at least one is absent or unverified; exit 2 means unsupported arguments.
JSON distinguishes program presence, socket ownership, protocol advertisement,
version query and lock state. It always reports assistant transport, screenshot
delivery, input delivery and voice routing as `not_tested`.

The probe requires an inherited Wayland session, an absolute user-owned private
runtime directory, and same-user Wayland/Hyprland sockets. It deliberately does
not scan other sessions, scrape a process's environment, guess socket names,
or use `/tmp/hypr` fallback locations. Nonstandard socket layouts can fail the
probe even when manually configured clients could work. Treat that as a result
to investigate, not permission to loosen ownership checks.

The only processes it can launch are `hyprctl -j version`, `hyprctl -j locked`,
and `wayland-info`, each with a five-second timeout and no shell evaluation.
Output includes no raw environment values, socket paths, serial numbers,
window titles, command stderr or full system information. Protocol presence is
not an input test and the ownership checks are not a security boundary against
other processes already running as the same user.

## Smallest supported on-device verification

Perform these in order; stop at the first missing permission or unavailable
capability. The screenshot and typing checks below have been performed on the
T14; pointer-adapter acceptance is tracked separately below.

1. The owner authorizes the intended computer for the dot through its supported
   connection UI. Confirm it is both connected and authorized. Being listed or
   online is insufficient. No other device should be substituted silently.
2. Start a local task on that exact computer. Inventory its actual tools before
   choosing a route: native screen/input tools if available, otherwise its
   approved shell/file tools. Do not assume this task inherits local MCP servers.
3. Run the read-only probe through that local task. Confirm the expected live
   Hyprland version, socket ownership and unlocked state. If the executor lacks
   the session environment, stop and determine a supported session-local launch
   method with the owner; do not recover credentials or scrape unrelated processes.
4. With explicit approval of the screen content being shared, capture one
   selected monitor into a private temporary file and have **that local task**
   inspect the actual pixels with its image tool. Confirm monitor identity,
   image dimensions and coordinate mapping. A filename in a cloud message is
   not evidence that screenshot delivery worked. Remove the test artifact when
   it is no longer needed, with the owner's permission.
5. Only after that observation loop works, approve a narrowly scoped input
   smoke test in an empty scratch window: focus it, type a harmless marker,
   click a harmless control, scroll, and verify each result with a fresh image.
   Test drag separately; wlrctl alone does not establish it. Do not test on
   credentials, terminals with commands, payment controls or live messages.
6. Verify cancellation, lock/logout, changed focus, stale screenshot and monitor
   hotplug handling. Then repeat one harmless task initiated through voice.
   Record which assistant session performed the action and how the result
   returned. If only local desktop Codex works, report that limitation explicitly.

## Adapter boundaries

Use a same-user, session-bound process launched for one authorized task. Local
Codex can own a STDIO MCP process; an authorized dot task can instead use a
bounded executable/file interface if its actual tools support that route.
The controller should expose typed operations, not a general `exec`, arbitrary
Lua evaluator or unrestricted hyprctl passthrough.

- Observation returns a screenshot plus monitor geometry and a short-lived
  observation identifier. Input refers to that observation, selected output and
  target window. Recheck lock state and target focus before each action.
- Express coordinates unambiguously. Convert screenshot pixels to logical
  desktop coordinates for scaled/rotated outputs. Reject stale output layouts,
  invalid coordinates and ambiguous window matches.
- Use compositor IPC for semantic window/workspace actions and Wayland virtual
  input for clicks, typing, scrolling and drag. Persistent pointer/key state
  belongs to the short-lived adapter. It sends releases on ordinary errors and
  handled cancellation before destroying its virtual device. A broken compositor
  connection or uncatchable process termination cannot guarantee that a release
  event reaches the application; device removal then depends on compositor
  behavior. Do not implement drag as independent wlrctl calls.
- Default to disabled. Require the owner's visible opt-in and an immediate stop
  control, bounded session lifetime, conservative operation limits, and
  approvals for consequential actions. Screen content is untrusted data and
  cannot authorize subsequent actions.
- Keep screenshots in memory or private temporary storage, minimize retention,
  and avoid logging typed text or screen content. No root daemon, input-group
  membership, udev permission change, broad screen-recording rule, network
  listener, new credential or remote tunnel is required by this design.
- Do not promise background per-app isolation. The same desktop session is
  shared with the user, and ordinary virtual input can affect the focused app.
  If those risks are unacceptable, use a separate restricted graphical session.

## Verification and remaining gaps

Offline tests cover the exact read-only command allowlist, missing executables,
missing protocols, command failures/timeouts, malformed and unknown lock state,
locked sessions, path traversal, wrong ownership, symlink rejection, private
runtime-directory permissions, output minimization, and the invariant that a
positive probe never claims working transport or control.

Run `python3 -m unittest discover -s tests -p 'test_hyprland_control_probe.py'`
and `nix build .#checks.x86_64-linux.hyprland-control-probe`. The normal aggregate
check remains `just check`. Before approving an actual controller, add protocol
integration tests in an isolated compositor, coordinate/rotation tests,
held-input cleanup tests, focus-race/cancellation tests and the on-device
acceptance sequence above.

Unit tests do not establish live screenshots, actual input delivery, dot
transport or voice routing. Device evidence below is limited to the exact
operations and task route tested; it does not replace pointer acceptance.

[linux]: https://learn.chatgpt.com/docs/linux/linux-app
[mcp]: https://learn.chatgpt.com/docs/extend/mcp
[dots]: https://learn.chatgpt.com/docs/dots/computers-and-apps
[voice]: https://learn.chatgpt.com/docs/features/voice
[plugins]: https://developers.openai.com/plugins/build/plugins
[hyprctl]: https://wiki.hypr.land/configuring/core/advanced-configuration/using-hyprctl/
[grim]: https://gitlab.freedesktop.org/emersion/grim
[wtype]: https://github.com/atx/wtype
[wlrctl]: https://git.sr.ht/~brocellous/wlrctl
[ydotool]: https://github.com/ReimuNotMoe/ydotool
[wayvnc]: https://github.com/any1/wayvnc
[protocols]: https://github.com/hyprwm/Hyprland/blob/v0.55.4/src/managers/ProtocolManager.cpp
[portal-prs]: https://github.com/hyprwm/xdg-desktop-portal-hyprland/pulls


## T14 evidence from the authorized connected-computer task

On 2026-10-03, a voice-coordinated local task inherited the existing Wayland,
Hyprland and user D-Bus session. Its shell could query the compositor with the
execution environment's approved escalation path. It had `view_image`, but no
general native desktop input tool. This establishes this particular task route;
it does not establish arbitrary cloud access to a local MCP server.

After the owner received a heads-up and said he was hands off, the task opened
an isolated Chrome profile on a static local scratch page. It rechecked the
scratch window's PID and title before using `grim` to capture only that window's
rectangle. The local task inspected the resulting pixels through `view_image`.
The capture was 2536 × 2788 pixels for a 1268 × 1394 logical rectangle at desktop
position (2726, 40), matching the selected output's scale of 2. The task then
rechecked focus, used the existing `wtype` executable to type a harmless marker,
and visually confirmed it in a fresh scratch-only screenshot. It closed only
the isolated scratch browser. No pointer click, scroll, or drag was established
by that test.

The owner subsequently logged out and in after the separate workspace/layout
activation. All further tasks must use their newly inherited session identity;
the earlier Hyprland socket identity must not be reused. The first read-only
check after login confirmed an unlocked session and the same two scale-2,
untransformed outputs. No session environment was recovered from other processes.

### Pointer adapter acceptance target

The adapter uses the official wlr virtual-pointer protocol with one short-lived
Wayland connection for an entire operation. In particular, drag is a sustained
button-down/path/button-up sequence; it is not synthesized from separate
`wlrctl` invocations. The guard checks an observation's freshness, target focus,
lock state, session identity, and output geometry. The initial implementation
rejects transformed outputs rather than guessing their coordinate mapping.

These checks reduce risk but do not make input atomic with focus or lock state.
The compositor and user can change state between a check and delivery. The
adapter is for a cooperative, explicitly authorized hands-off interval, not
background per-application isolation. A screenshot, observation file, or page
instruction is never authorization to act.

The static fixture `tests/fixtures/pointer-scratch.html` provides visible click,
scroll, and drag counters without network requests, forms, or persistent state.
Before opening it or injecting input, convey the exact proposed test to the
owner and wait for the coordinating session to confirm the heads-up reached
him. Stop input when he resumes using the desktop. Offline implementation and
tests can continue without holding the user idle.

### Observation and coordinate contract

The first adapter version deliberately accepts only the currently focused
window, wholly contained on one output. Every output in the layout must be
untransformed and use scale 1 or 2. It rejects cross-output windows and
unsupported scales/transforms. `observe` takes an
explicit target window address, captures that window itself with `grim`, and
checks the session, lock, focus, window rectangle and output layout both before
and after capture. It creates new private PNG and JSON files; it does not stamp
an arbitrary old screenshot as a fresh observation.

Action coordinates are integer pixels within that cropped PNG, not full-screen
coordinates. A crop pixel `(px, py)` maps to logical desktop coordinates
`(window_x + px / scale, window_y + py / scale)`. The monitor's origin and extent
then determine the virtual-pointer absolute position. Negative desktop origins
must be included rather than treating the desktop's origin as `(0, 0)`.

The observation lasts at most 30 seconds, allowing the screenshot to pass through
the local image tool. It becomes invalid sooner if the session, focus, target
window rectangle, or any output geometry changes. Every input event rechecks
those conditions and lock state. If validation fails, take a new observation
and inspect it; do not refresh timestamps or replay the old request blindly.

The coordinate model follows the pinned Hyprland 0.55.4 implementations of
[`VirtualPointer.cpp`](https://github.com/hyprwm/Hyprland/blob/v0.55.4/src/protocols/VirtualPointer.cpp)
and [`PointerManager.cpp`](https://github.com/hyprwm/Hyprland/blob/v0.55.4/src/managers/PointerManager.cpp):
unbound virtual-pointer absolute coordinates span the bounding box of the
logical output layout. This is compositor-specific behavior; a different
compositor or changed input mapping requires separate validation.

Each button or scroll event carries its own validated crop coordinates. The
helper emits the absolute movement and that event in one pointer frame, so a
click or scroll does not rely on wherever the user's cursor happened to be.
The public action interface exposes only move, three ordinary mouse buttons,
and bounded wheel steps. It does not expose arbitrary Lua, shell execution,
keyboard text, or general compositor dispatch.

### Explicit task invocation

Build the reviewed package with `nix build .#hyprland-pointer-adapter`; this does
not install or enable it in Home Manager. Its public executable is
`result/bin/hyprland-pointer-adapter`. The raw protocol helper is internal
`libexec` machinery, not a supported unguarded control interface. These checks
are not protection against another process with the same user's shell access.

During an authorized hands-off scratch test, use a new private temporary
directory and an explicitly identified, currently focused scratch-window
address:

```sh
umask 077
scratch_run=$(mktemp -d)
result/bin/hyprland-pointer-adapter observe \
  --target-window 0xREPLACE_WITH_VERIFIED_SCRATCH_ADDRESS \
  --screenshot "$scratch_run/observation.png" \
  --output "$scratch_run/observation.json"
```

Inspect the actual PNG through the task's image tool before constructing an
action. Keep the observation and action files private. An example click request
uses the observation's exact `observation_id` and a point chosen from the fresh
scratch image:

```json
{
  "schema_version": 1,
  "observation_id": "REPLACE_WITH_OBSERVATION_ID",
  "actions": [
    {"type": "button", "button": "left", "state": "down", "x": 120, "y": 240},
    {"type": "button", "button": "left", "state": "up", "x": 120, "y": 240}
  ]
}
```

The sample coordinates are illustrative, not safe defaults for another window.
Save the reviewed request as a mode-0600 `actions.json`, then invoke:

```sh
result/bin/hyprland-pointer-adapter act \
  --observation "$scratch_run/observation.json" \
  --actions "$scratch_run/actions.json"
```

A move is `{"type":"move","x":120,"y":240}`. A vertical wheel request is
`{"type":"scroll","dx":0,"dy":2,"x":120,"y":240}`. Each wheel component is
an integer from -20 to 20. Drag uses a button-down event, a bounded series of
move events, and a button-up event in the **same** request. Requests contain at
most 64 actions and must leave no buttons held. The input worker is short-lived;
there is no idle daemon. Interrupting the wrapper forwards cancellation to its
helper and initiates cleanup. Do not deliberately test cancellation on a real
application with unsaved or consequential work.

Take a fresh observation and inspect its pixels after each meaningful scratch
action. Successful process exit establishes that protocol operations completed;
the fresh image establishes whether the application responded as intended.

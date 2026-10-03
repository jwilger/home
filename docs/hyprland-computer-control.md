# Hyprland computer control: feasibility and first verification

Research date: 2026-10-03. Repository baseline: `96b26df`.

## Recommendation

The local display/input building blocks exist. The first unresolved requirement
is connecting the **intended assistant session** to them with the user's
authorization and returning actual screenshots. Installing an automation CLI
alone does not meet the goal of talking to Jarvis and having it observe and
operate the desktop.

Start with the supported connected-computer task route and prove that a local
task can observe the intended unlocked Hyprland session. Only then implement
an input adapter for that executor. If local desktop Codex is the chosen
consumer instead, a session-local STDIO MCP adapter is a documented extension
point. Neither route establishes that the cloud dot's voice session can call
that MCP server directly.

This change adds an **opt-in read-only readiness probe**, not a controller.
Both existing profiles leave it disabled. It does not capture pixels, enumerate
window titles, inject input, register MCP, start a service, grant permissions,
add credentials, or expose a network listener. Nothing is activated by this PR.

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
capability. None has been run on a user's device for this PR.

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

## Proposed adapter once transport is proven

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
  belongs to the short-lived adapter, with guaranteed release on error,
  disconnect and cancellation. Do not implement drag as independent wlrctl calls.
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

No unit test here establishes live screenshots, actual input delivery, dot
transport or voice routing. Those are explicit gates for the next increment.

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

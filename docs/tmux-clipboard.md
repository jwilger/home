# Clipboard across persistent tmux sessions

## Which clipboard?

The **computer displaying WezTerm owns the clipboard**. Locally that is the Linux desktop; over SSH from a Mac that is the Mac, not the Linux server. OSC 52 carries copied text back through the terminal connection. No SSH clipboard forwarding, desktop socket forwarding, or clipboard-reading daemon is needed.

This is text-copy integration, not continuous clipboard synchronisation. The Linux clipboard and primary selection remain distinct; macOS has no equivalent primary selection. Do not depend on remote TUIs reading either system clipboard.

## Everyday use

- **tmux keyboard copy:** Ctrl+A, then `[`, navigate, `v` to start selecting, then `y` or Enter to copy and exit copy mode. The text also remains in tmux's paste buffer (Ctrl+A, then `]`).
- **Mouse copy:** drag and release in a tmux pane. A TUI that captures mouse events may handle the drag itself; use tmux copy mode in that case. WezTerm's terminal selection (normally Shift-drag when bypassing application mouse handling) is another fallback.
- **Helix:** Space, `y` copies the selection to the displaying computer. The configured `termcode` provider writes only; for system paste, enter insert mode and use WezTerm's paste shortcut. Helix's ordinary `y` still yanks to its own register.
- **Lazygit:** use its normal copy menus (`y` on a commit, then `m` for its message). Its copy command encodes the shell-quoted text as OSC 52 and writes to `/dev/tty`, because command stdout is captured by Lazygit.
- **Paste from another app:** Cmd+V on a Mac, Ctrl+Shift+V on Linux. These are WezTerm shortcuts; no tmux prefix is involved. For editor insertions, put the TUI into the appropriate input mode first.

WezTerm supports OSC 52 clipboard writes without additional configuration on either Mac. Retain its normal clipboard paste shortcuts. This repository manages the Linux configuration, not the laptops' configuration.

## Applying without losing sessions

Build and activate the appropriate Home Manager configuration using the normal workflow, then reload **each existing tmux server**:

```sh
tmux source-file ~/.config/tmux/tmux.conf
```

Ctrl+A, then `r` does the same thing. Detach (Ctrl+A, then `d`) and reattach from WezTerm so the client terminal features are refreshed. Do not run `tmux kill-server`: the sessions and their processes should stay alive. Restart Helix and Lazygit to pick up their new application configuration. For Pi in an already running shell, run `export PI_CLIPBOARD_OSC52=1` before restarting Pi. New login shells receive this through Home Manager; tmux's existing processes do not automatically inherit updated session variables.

Removing tmux-yank alone would leave its old key bindings in a running server. The new configuration explicitly replaces keyboard and mouse copy bindings, clears `copy-command`, and removes the plugin's obsolete prefix `y`/`Y` and copy-mode `Y`/`M-y`/`!` shortcuts (plus its emacs-mode `y`). Those plugin-only shortcuts are no longer supported; use the everyday actions above. Reload therefore does not retain their host-local copy paths. Existing `WAYLAND_DISPLAY`/`DISPLAY` values no longer determine their clipboard destination.

## Trust boundary

Programs in visible tmux panes can write the displaying computer's clipboard. That includes programs running over SSH; treat copied text as untrusted, especially before pasting into a shell. `set-clipboard on` accepts application OSC 52; `allow-passthrough on` additionally allows tmux-wrapped terminal sequences from visible panes (not just clipboard sequences). It deliberately does not use `all`, which would also pass through from invisible panes. This setup adds no clipboard-read bridge, but does not disable capabilities the terminal itself already permits. Multiple simultaneously attached clients can receive clipboard writes; this is not per-user clipboard isolation.

## Automated evidence

```sh
nix build .#checks.x86_64-linux.tmux-clipboard --no-link -L
```

The check launches real pinned tmux, Helix and Lazygit processes with generated Home Manager configuration, a private tmux socket, isolated HOME, and a PTY standing in for WezTerm. It checks exact OSC 52 payloads and traps host clipboard commands under a deliberately stale display environment. Coverage includes keyboard and mouse copy, plain and tmux-wrapped application copy, detach/reattach, foreground-process paste, Helix Unicode yank, and Lazygit Unicode/shell-metacharacter copy. It never sends test clipboard sequences to the real desktop terminal. For sandbox execution only, plugin entry points are invoked with an explicit Nix-store Bash instead of their `/usr/bin/env bash` shebang (the sandbox has no `/usr/bin/env`); all generated tmux commands are retained. Reload coverage seeds old host-copy bindings, sources the configuration, then checks keyboard/mouse copying and session survival.

These tests prove terminal-bound bytes, **not** end-to-end delivery into a real Linux or macOS clipboard.

## Native TUI audit (installed versions, October 2026)

The tmux/Helix/Lazygit paths above avoid server-local clipboard commands. Other applications can still make **duplicate native writes**; the terminal integration does not intercept or disable them. There is no supported universal terminal-only setting across these applications, so do not globally hide or replace `wl-copy`/`xclip` to force it.

| Application | Native-copy behavior and limitations |
| --- | --- |
| **Pi 1.4.0** | `PI_CLIPBOARD_OSC52=1` (set in `modules/home/environment.nix`) also emits raw OSC 52 even when persistent tmux has stale display variables and no SSH markers. It does **not** suppress its preceding native copy. Its OSC 52 limit is 100,000 base64 characters (about 75 KiB of UTF-8 bytes); use selection/chunks for larger copies. |
| **Codex 0.163.0** | Forwards through `tmux load-buffer -w`; it can additionally access Wayland/X11 directly via `arboard`, so merely checking for helper executables is not sufficient to rule out native writes. No supported terminal-only switch was found. |
| **Claude Code 2.1.310** | Installed bundle uses tmux buffer/OSC 52 routes, including a wrapped duplicate, and normally also native Linux copy locally. It skips native Linux writes when SSH is detected; stale persistent-server environment can affect that detection. No supported terminal-only switch was found. This is installed-bundle inspection, not a published-source guarantee. |
| **Yazi 26.5.6** | Source emits raw OSC 52, then tries native clipboard helpers. Its current configuration fails to start because two pre-existing `name` selectors now require `url`/`mime` (``at least one of `url` or `mime` must be specified``). Clipboard behavior is therefore **source-audited, not runtime verified**. Migrating the Yazi configuration is separate work. |

Where native copy is unsuitable or unsupported, use tmux copy mode to select the visible text. This fallback cannot copy text the TUI never renders; use that application's export feature first if needed. Terminal shortcut paste remains the supported way to bring desktop clipboard text into these TUIs.

Audit references:

- [Pi clipboard implementation](https://github.com/earendil-works/pi/blob/4a080252f06caf63a525d7873c5d94d3c23887e0/packages/coding-agent/src/utils/clipboard.ts#L86-L150) and the matching installed `dist/utils/clipboard.js`. An isolated local probe using the generated session variables confirmed exact OSC 52 output with stale display state and no SSH markers; it also confirmed the native-copy duplicate. This machine-specific probe is separate from the reproducible Nix check.
- [Codex clipboard routing](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/tui/src/clipboard_copy.rs#L179-L245) and [tmux forwarding](https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/tui/src/clipboard_copy/tmux.rs#L45-L120).
- [Yazi clipboard setter](https://github.com/sxyazi/yazi/blob/aa526434f00bb44e2e902d9a4ac5f810da1018b9/yazi-widgets/src/clipboard.rs#L52-L92) and [selector parsing](https://github.com/sxyazi/yazi/blob/aa526434f00bb44e2e902d9a4ac5f810da1018b9/yazi-config/src/selector.rs#L7-L40).
- [Claude Code tmux guidance](https://code.claude.com/docs/en/terminal-config#configure-tmux). Native behavior was inspected in the installed 2.1.310 bundle; re-check on upgrades.
- [Lazygit template quoting](https://github.com/jesseduffield/lazygit/blob/d167063b4f45d044524f3fba97f850d1eec3f95c/pkg/commands/oscommands/os.go#L269-L287). The exact payload is also tested through its real UI.

## Live acceptance checklist (still manual)

Run this separately on the local Linux desktop and over SSH from **each** Mac:

- [ ] Copy a unique line with tmux `y`; paste it into a non-terminal app.
- [ ] Repeat with mouse selection and with Helix Space, `y`.
- [ ] Copy a Lazygit commit message containing Unicode; paste into another app.
- [ ] Copy text in another app and paste with the platform's WezTerm shortcut into a shell and a TUI input field. Do not execute unknown shell text.
- [ ] Detach, close the terminal/SSH connection, reconnect, reattach, and repeat both directions.
- [ ] Check the application-specific native-copy limitations below; use tmux selection wherever native copy is unsupported.

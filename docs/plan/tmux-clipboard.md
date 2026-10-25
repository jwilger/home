# Terminal-owned clipboard implementation

## clipboard — Copy to the attached terminal

**Goal:** Copies inside persistent tmux reach the displaying terminal rather than depending on the server's desktop clipboard.

**Files:** modules/home/tmux.nix, modules/home/helix/default.nix, modules/home/lazygit.nix, modules/home/environment.nix as supported by the TUI audit; flake.nix; tests/test_tmux_clipboard.py; docs/tmux-clipboard.md.

**Interfaces:** Existing tmux copy-mode bindings and OSC 52 output, Helix clipboard-provider, Lazygit os.copyToClipboardCmd; no new service or remote clipboard-read contract.

**First failing test:** With the generated tmux config and a host clipboard sentinel, selecting text and pressing copy-mode y emits the exact OSC 52 payload to the attached PTY without invoking the sentinel.

**Steps:**
1. Exercise native keyboard copy through a private tmux socket and PTY, then remove tmux-yank's competing host-local path.
2. Test plain and tmux-wrapped application OSC 52, mouse copy and terminal paste after reattach.
3. Drive Helix and Lazygit copy through their generated configs, including Unicode and shell metacharacters.
4. Record TUI audit evidence, supported settings, fallbacks and non-destructive reload instructions.
5. Run both Home Manager builds, the clipboard check and fresh-context review.

**Run:** nix build .#checks.x86_64-linux.tmux-clipboard -L

**Expected:** Behavioral PTY tests pass, without touching the real system clipboard.

**Out of scope:** Clipboard reads, forwarding daemons, changing other apps' default clipboard tools globally, fixing pre-existing Yazi config migration. OSC 52 already exists here; no new architecture or dependency class. Clipboard writes can be initiated by pane programs (existing set-clipboard on); the user-approved terminal-owned approach does not add clipboard-read authority.

## Test list

- [x] Keyboard y emits selected bytes, no host clipboard command.
- [x] Mouse release copies without a host clipboard command.
- [x] Plain OSC 52 is relayed.
- [x] Tmux-wrapped OSC 52 is relayed.
- [x] Reattached terminal receives subsequent copies and can paste into foreground process.
- [x] Reload replaces seeded old host-copy bindings without losing the session.
- [x] Helix system yank uses terminal bytes, including Unicode.
- [x] Lazygit copy preserves shell metacharacters and Unicode.
- [x] Native TUI limitations documented; Linux and both Mac live checks remain explicit.

## Verification evidence

- `nix build .#checks.x86_64-linux.tmux-clipboard --no-link -L`: eight real-process PTY tests passed.
- Both `homeConfigurations."jwilger@gregor".activationPackage` and `homeConfigurations."jwilger@jwilger-t14".activationPackage` built successfully; neither was activated.
- `nix flake check -L`: all flake checks passed, including both Home Manager activation builds.
- Installed Pi 1.4.0 probe: with no SSH markers and a fake successful `wl-copy`, generated session variables initially produced no OSC 52; after setting `PI_CLIPBOARD_OSC52=1`, exact Unicode OSC 52 bytes were captured. Native copy still occurs, as documented.
- Upstream plugin `/usr/bin/env bash` entry points cannot run directly in the Nix sandbox. The check invokes those same scripts with explicit Nix-store Bash rather than dropping plugins or ignoring reload failures.
- Review found old tmux-yank prefix/copy-mode shortcuts survived reload. Extending the real-keypress reload test reproduced `Reload retained a legacy prefix copy binding`; explicitly retiring all plugin-only shortcuts made all eight tests pass again.
- Real Linux and both Mac clipboard round trips remain manual acceptance work in `docs/tmux-clipboard.md`.

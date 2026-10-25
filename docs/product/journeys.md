# Clipboard journeys

- **J1 Local:** select terminal text in tmux, copy, paste into another Linux app; copy text in that app and paste into a tmux TUI with Ctrl+Shift+V.
- **J2 SSH:** attach the same persistent session from either Mac in WezTerm, copy terminal/TUI text, paste into a Mac app; paste app text back with Cmd+V.
- **J3 Reattach:** detach from one computer, attach from another, and repeat J1/J2 without restarting tmux or its applications. Clipboard destination follows the attached terminal, not the server's desktop environment.
- **J4 App copy:** use Helix system yank and Lazygit copy; audit Pi, Codex, Claude Code and Yazi. Where native copy cannot target the client reliably, use tmux selection and explain the limitation.

Acceptance: automated terminal-output checks plus the live checklist in docs/tmux-clipboard.md. No automatic clipboard reads from the SSH client are required.
